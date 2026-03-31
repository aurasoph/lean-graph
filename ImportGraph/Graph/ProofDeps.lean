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

/-
Proof dependency graph construction based on constant values/implementations.
This extracts dependencies from theorem proofs and definition bodies,
revealing the actual computational and propositional dependencies.
-/

namespace Lean.Environment

/--
Get the "parent" declaration for a mechanical/auto-generated declaration.
This is used for transitive closure when filtering.

Examples:
- `List.length.eq_def` → `List.length`
- `Nat.succ.injEq` → `Nat.succ` (preserved, but pattern still works)
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
Check if a name represents a mechanical/compiler-generated declaration that
has no mathematical content. These are always filtered regardless of flags.

Filtered categories:
- `.eq_def`, `.eq_1`, `.eq_2`, etc. - definitional unfolding lemmas
- `.sizeOf_spec` - termination checker metadata  
- `.ctorIdx` - runtime constructor index

NOT filtered (these have mathematical meaning):
- `.injEq` - constructor injectivity (e.g., succ x = succ y ↔ x = y)
- `.noConfusion` - constructor distinctness
- `.rec`, `.recOn`, `.casesOn` - induction principles
-/
private def isMechanicalDeclarationLogic (name : Name) : Bool :=
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
Determines whether a constant should be included in the proof dependencies graph.
Uses the same filtering logic as TypeDeps for consistency.
-/
private def shouldIncludeConstantLogic (env : Environment) (name : Name) 
    (includeAux : Bool) (includeInstances : Bool) : CoreM Bool := do
  -- Always filter mechanical declarations (no mathematical content)
  if isMechanicalDeclarationLogic name then
    return false
  else if includeAux && includeInstances then
    return true
  else
    -- Check for auxiliary/generated declarations
    let isAux := name.isInternalDetail || isAuxRecursor env name || isNoConfusion env name
    
    if !includeAux && isAux then
      return false
    else if !includeInstances then
      -- Use Lean's Meta.isInstance to accurately detect typeclass instances
      let isInst ← Meta.isInstance name
      if isInst then
        return false
      else
        return true
    else
      return true

/--
Apply transitive closure when filtering dependencies.
For each filtered dependency that is auto-generated from a base declaration,
replace it with a dependency on the base declaration.

This preserves conceptual dependencies when filtering out compiler-generated noise.

Examples:
- If theorem depends on `List.length.eq_def` (filtered), add dependency on `List.length`
- If theorem depends on `Color.ctorIdx` (filtered), add dependency on `Color`
-/
def applyTransitiveClosure (env : Environment) (deps : Array Name) 
    (includeAux : Bool) (includeInstances : Bool) : CoreM (Array Name) := do
  let mut result : Array Name := #[]
  let mut seen : NameSet := {}
  
  for dep in deps do
    let shouldIncludeDep ← shouldIncludeConstantLogic env dep includeAux includeInstances
    if shouldIncludeDep then
      -- Keep this dependency as-is
      if !seen.contains dep then
        result := result.push dep
        seen := seen.insert dep
    else if isMechanicalDeclarationLogic dep then
      -- This is a filtered mechanical declaration - find its parent
      let parent := getParentDeclaration dep
      -- Only add parent if it exists in environment and should be included
      if parent != dep && env.contains parent then
        let shouldIncludeParent ← shouldIncludeConstantLogic env parent includeAux includeInstances
        if shouldIncludeParent then
          if !seen.contains parent then
            result := result.push parent
            seen := seen.insert parent
      -- If no valid parent found, dependency is dropped (as before)
    
    -- For other filtered dependencies (aux, instances), just drop them (as before)
  
  return result

/--
Build a proof dependencies graph from the Lean environment.

For each constant in the environment:
- **Theorems** (`.thmInfo`): Extract constants used in the proof body
- **Definitions** (`.defnInfo`): Extract constants used in the definition body
- **Recursors** (`.recInfo`): Extract constants used in the recursor implementation
- **Terminal nodes** (axioms, inductives, constructors, opaque, quotients): 
  Add to graph with no dependencies

The result is a `NameMap (Array Name)` where:
- Key: The constant name
- Value: Array of constants it depends on (empty for terminal nodes)

Parameters:
- `env`: The Lean environment to analyze
- `includeAux`: If `false`, filter out auxiliary declarations
- `includeInstances`: If `false`, filter out typeclass instances
-/
public def proofDepsGraph (env : Environment) 
    (includeAux : Bool) (includeInstances : Bool) : CoreM (NameMap (Array Name)) := do
  let mut graph : NameMap (Array Name) := {}
  
  for (name, info) in env.constants.toList do
    -- Apply filtering to source node
    let shouldInclude ← shouldIncludeConstantLogic env name includeAux includeInstances
    if !shouldInclude then continue
    
    match info with
    | .thmInfo val =>
      -- Theorems: extract constants from proof body
      let deps := val.value.getUsedConstants
      -- Apply transitive closure for filtered dependencies
      let processedDeps ← applyTransitiveClosure env deps includeAux includeInstances
      graph := graph.insert name processedDeps
      
    | .defnInfo val =>
      -- Definitions: extract constants from definition body
      let deps := val.value.getUsedConstants
      -- Apply transitive closure for filtered dependencies
      let processedDeps ← applyTransitiveClosure env deps includeAux includeInstances
      graph := graph.insert name processedDeps
      
    -- Terminal nodes (axioms, inductives, constructors, opaque, quotients, recursors)
    -- are NOT added as source nodes - they have no outgoing edges.
    -- They will appear as targets when referenced by theorems/definitions.
    | .recInfo _ | .axiomInfo _ | .inductInfo _ | .ctorInfo _ | .opaqueInfo _ | .quotInfo _ =>
      continue
  
  return graph

end Lean.Environment
