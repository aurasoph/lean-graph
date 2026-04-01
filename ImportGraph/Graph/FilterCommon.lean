/-
Copyright (c) 2024 ImportGraph Contributors. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: ImportGraph Contributors
-/
module

public import Lean.Environment
public import Lean.CoreM
import Lean.Meta.Instances

open Lean Meta

/-!
# Common Filtering Logic for Dependency Graphs

Shared filtering utilities used by TypeDeps and ProofDeps graphs to identify
and filter mechanical/compiler-generated declarations.
-/

namespace Lean.Environment

/--
Determine if a constant name represents a mechanical/compiler-generated declaration.
These declarations provide no mathematical insight and create noise in dependency analysis.

Filtered patterns:
- `.eq_def` - definitional equality lemmas
- `.eq_1`, `.eq_2`, etc. - equation lemmas  
- `.sizeOf_spec` - termination checker artifacts
- `.ctorIdx`, `_ctorIdx` - runtime constructor indices
-/
public def isMechanicalDeclaration (name : Name) : Bool :=
  let s := name.toString
  s.endsWith ".eq_def" || 
  ((s.splitOn ".eq_").length > 1 && s.back.isDigit) ||
  s.endsWith ".sizeOf_spec" ||
  s.endsWith ".ctorIdx" || s.endsWith "_ctorIdx"

/--
Get the "parent" declaration for a mechanical/auto-generated declaration.
Used for transitive closure - when filtering `List.length.eq_def`, we redirect
to a dependency on `List.length` instead.

Examples:
- `List.length.eq_def` → `List.length`
- `UInt16.ofBitVec.sizeOf_spec` → `UInt16.ofBitVec`
- `Color.ctorIdx` → `Color`
-/
public def getParentDeclaration (name : Name) : Name :=
  let s := name.toString
  if s.endsWith ".eq_def" then
    (s.dropEnd ".eq_def".length).toString.toName
  else if (s.splitOn ".eq_").length > 1 && s.back.isDigit then
    let parts := s.splitOn ".eq_"
    if parts.length >= 2 then parts[0]!.toName else name
  else if s.endsWith ".sizeOf_spec" then
    (s.dropEnd ".sizeOf_spec".length).toString.toName
  else if s.endsWith ".ctorIdx" then
    (s.dropEnd ".ctorIdx".length).toString.toName
  else if s.endsWith "_ctorIdx" then
    (s.dropEnd "_ctorIdx".length).toString.toName
  else
    name

/-- Check if a constant should be included in dependency graphs. -/
public def shouldIncludeConstant (env : Environment) (name : Name) 
    (includeAux : Bool) (includeInstances : Bool) : CoreM Bool := do
  -- Always filter mechanical declarations
  if isMechanicalDeclaration name then
    return false
    
  if includeAux && includeInstances then
    return true
  
  -- Check for auxiliary/generated declarations
  let isAux := name.isInternalDetail || isAuxRecursor env name || isNoConfusion env name
  if !includeAux && isAux then
    return false
  
  -- Check for typeclass instances
  if !includeInstances then
    let isInst ← Meta.isInstance name
    if isInst then return false
  
  return true

/--
Apply transitive closure when filtering dependencies.
For filtered mechanical declarations, redirect to their parent declaration.
-/
public def applyTransitiveClosure (env : Environment) (deps : Array Name) 
    (includeAux : Bool) (includeInstances : Bool) : CoreM (Array Name) := do
  let mut result : Array Name := #[]
  let mut seen : NameSet := {}
  
  for dep in deps do
    let shouldInclude ← shouldIncludeConstant env dep includeAux includeInstances
    if shouldInclude then
      if !seen.contains dep then
        result := result.push dep
        seen := seen.insert dep
    else if isMechanicalDeclaration dep then
      let parent := getParentDeclaration dep
      if parent != dep && env.contains parent then
        let parentOk ← shouldIncludeConstant env parent includeAux includeInstances
        if parentOk && !seen.contains parent then
          result := result.push parent
          seen := seen.insert parent
  
  return result

end Lean.Environment
