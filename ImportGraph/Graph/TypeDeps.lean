/-
Copyright (c) 2024 ImportGraph Contributors. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: ImportGraph Contributors
-/
module

public import Lean.Environment
public import Lean.CoreM
import Lean.Data.NameMap.Basic
import Lean.Meta.Match.MatcherInfo
import Lean.Meta.Instances

open Lean Meta

/-!
# Type Dependency Graph (Blueprint Mode)

This module constructs a dependency graph based on type signatures.
For each constant (theorem, definition, etc.), we extract all constants
mentioned in its type signature.

This is useful for understanding the "blueprint" of dependencies - what types
are needed to even state a theorem or definition, independent of its proof or implementation.

## Example

For `theorem foo (n : Nat) : List Nat := ...`
- Type signature: `Nat → List Nat`
- Dependencies extracted: `Nat`, `List`

This differs from proof dependencies (Logic mode) which would look at the body `...`.

## Design Decisions

### Instance Filtering (Default: ON)

**By default, typeclass instances are filtered out** unless `--include-instances` is used.

**Rationale**:
- Instances create "star patterns" (every type → 5-10 instance nodes)
- Instances are mechanically derived from type definitions
- For dependency analysis, instances are implied (if `Point` exists, so does `instToJsonPoint`)
- Reduces graph size significantly (patrik-cihal reports "orders of magnitude")
- Cleaner visualization and ML training data

**What gets filtered**: All typeclass instances like:
- `instToJson`, `instFromJson` - serialization
- `instBEq`, `instHashable` - data structure operations
- `instInhabited`, `instRepr` - defaults and printing
- `instGroup`, `instRing` - even mathematical instances

**Why filter mathematical instances too**: 
Lean is used for both math and programming. Distinguishing "mathematical vs programmatic" 
instances is subjective and fragile. Better to filter all instances uniformly.

**Access with**: `--include-instances` flag restores instance nodes.

-/

namespace Lean.Environment

/--
Determine if a constant name represents a mechanical/compiler-generated declaration.
These declarations provide no mathematical insight and create noise in dependency analysis.
-/
private def isMechanicalDeclaration (name : Name) : Bool :=
  let s := name.toString
  -- eq_def and eq_1, eq_2, etc. (definitional unfolding)
  s.endsWith ".eq_def" || 
  -- Check for .eq_N pattern (N is digit) using splitOn
  ((s.splitOn ".eq_").length > 1 && s.back.isDigit) ||
  -- sizeOf_spec (termination checker)
  s.endsWith ".sizeOf_spec" ||
  -- ctorIdx (runtime metadata) - can be .ctorIdx or _ctorIdx
  s.endsWith ".ctorIdx" || s.endsWith "_ctorIdx"

/--
Get the "parent" declaration for a mechanical/auto-generated declaration.
This is used for transitive closure when filtering.

Examples:
- `List.length.eq_def` → `List.length`
- `UInt16.ofBitVec.sizeOf_spec` → `UInt16.ofBitVec`
- `Color.ctorIdx` → `Color`
-/
private def getParentDeclaration (name : Name) : Name :=
  let s := name.toString
  if s.endsWith ".eq_def" then
    (s.dropEnd ".eq_def".length).toString.toName
  else if (s.splitOn ".eq_").length > 1 && s.back.isDigit then
    -- Handle .eq_1, .eq_2, etc.
    let parts := s.splitOn ".eq_"
    if parts.length >= 2 then
      parts[0]!.toName
    else name
  else if s.endsWith ".sizeOf_spec" then
    (s.dropEnd ".sizeOf_spec".length).toString.toName
  else if s.endsWith ".ctorIdx" then
    (s.dropEnd ".ctorIdx".length).toString.toName
  else if s.endsWith "_ctorIdx" then
    (s.dropEnd "_ctorIdx".length).toString.toName
  else
    name  -- No parent found, return original

/--
Extract type dependencies for a single constant.
Returns all constants mentioned in the type signature.
-/
private def getTypeDependencies (info : ConstantInfo) : Array Name :=
  info.type.getUsedConstants

/-- Check if a constant should be included in the type dependency graph. -/
private def shouldIncludeConstant (env : Environment) (name : Name) 
    (includeAux : Bool) (includeInstances : Bool) : CoreM Bool := do
  -- Always filter mechanical declarations (no mathematical content)
  if isMechanicalDeclaration name then
    return false
    
  if includeAux && includeInstances then
    return true
  
  -- Check for auxiliary/generated declarations
  let isAux := name.isInternalDetail || isAuxRecursor env name || isNoConfusion env name
  
  if !includeAux && isAux then
    return false
  
  -- Check for typeclass instances using Lean's builtin API
  if !includeInstances then
    -- Use Lean's Meta.isInstance to accurately detect typeclass instances
    let isInst ← Meta.isInstance name
    if isInst then
      return false
  
  return true

-- Apply transitive closure when filtering dependencies.
-- For each filtered dependency that is auto-generated from a base declaration,
-- replace it with a dependency on the base declaration.
--
-- This preserves conceptual dependencies when filtering out compiler-generated noise.
def applyTransitiveClosureTypeDeps (env : Environment) (deps : Array Name) 
    (includeAux : Bool) (includeInstances : Bool) : CoreM (Array Name) := do
  let mut result : Array Name := #[]
  let mut seen : NameSet := {}
  
  for dep in deps do
    let shouldInclude ← shouldIncludeConstant env dep includeAux includeInstances
    if shouldInclude then
      -- Keep this dependency as-is
      if !seen.contains dep then
        result := result.push dep
        seen := seen.insert dep
    else if isMechanicalDeclaration dep then
      -- This is a filtered mechanical declaration - find its parent
      let parent := getParentDeclaration dep
      -- Only add parent if it exists in environment and should be included
      if parent != dep && env.contains parent then
        let parentShouldInclude ← shouldIncludeConstant env parent includeAux includeInstances
        if parentShouldInclude && !seen.contains parent then
          result := result.push parent
          seen := seen.insert parent
      -- If no valid parent found, dependency is dropped (as before)
    
    -- For other filtered dependencies (aux, instances), just drop them (as before)
  
  return result

/-- Build type dependency graph based on constant type signatures. -/
public def typeDepsGraph (env : Environment) 
    (includeAux : Bool := false) (includeInstances : Bool := false) :
    CoreM (NameMap (Array Name)) := do
  let mut graph : NameMap (Array Name) := {}
  
  for (name, info) in env.constants.toList do
    -- Check if this constant should be included
    let shouldInclude ← shouldIncludeConstant env name includeAux includeInstances
    if shouldInclude then
      -- Extract all constants from the type signature
      let deps := getTypeDependencies info
      -- Apply transitive closure for filtered dependencies
      let processedDeps ← applyTransitiveClosureTypeDeps env deps includeAux includeInstances
      graph := graph.insert name processedDeps
  
  return graph

end Lean.Environment
