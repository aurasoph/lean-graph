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
  match name with
  | .str _ "eq_def" => true
  | .str _ "sizeOf_spec" => true
  | .str _ "ctorIdx" => true
  | .str _ suffix => 
    -- Check for .eq_N pattern (e.g., eq_1, eq_2) or _ctorIdx
    (suffix.startsWith "eq_" && (suffix.drop 3).all Char.isDigit && suffix.length > 3) ||
    suffix == "_ctorIdx"
  | _ => false

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
  match name with
  | .str parent "eq_def" => parent
  | .str parent "sizeOf_spec" => parent
  | .str parent "ctorIdx" => parent
  | .str parent "_ctorIdx" => parent
  | .str parent suffix =>
    -- Handle .eq_N pattern (e.g., eq_1, eq_2)
    if suffix.startsWith "eq_" && (suffix.drop 3).all Char.isDigit && suffix.length > 3 then
      parent
    else
      name
  | _ => name

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
