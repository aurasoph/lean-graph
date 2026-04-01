/-
Copyright (c) 2024 ImportGraph Contributors. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: ImportGraph Contributors
-/
module

public import Lean.Environment
public import Lean.CoreM
import ImportGraph.Graph.FilterCommon
import Lean.Data.NameMap.Basic
import Lean.Meta.Match.MatcherInfo

open Lean Meta

/-!
# Proof Dependency Graph (Logic Mode)

Constructs a dependency graph based on proof bodies and definition values.
Unlike type dependencies, this extracts constants from the actual implementations.

For theorems: dependencies from the proof body
For definitions: dependencies from the definition body
-/

namespace Lean.Environment

-- Chunked version of applyTransitiveClosure to handle large dependency arrays
private def applyTransitiveClosureChunked (env : Environment) (deps : Array Name) 
    (includeAux : Bool) (includeInstances : Bool) : CoreM (Array Name) := do
  let mut result : Array Name := #[]
  let mut seen : NameSet := {}
  
  -- Process dependencies in smaller batches to avoid stack buildup
  let chunkSize := 50  -- Small chunks to prevent recursion depth issues
  let depsCount := deps.size
  
  for startIdx in List.range (depsCount / chunkSize + 1) do
    let start := startIdx * chunkSize
    let endIdx := min (start + chunkSize) depsCount
    
    for i in List.range (endIdx - start) do
      if start + i >= depsCount then break
      let dep := deps[start + i]!
      
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

/--
Build a proof dependencies graph from the Lean environment.

For each constant:
- **Theorems**: Extract constants used in the proof body
- **Definitions**: Extract constants used in the definition body
- **Terminal nodes** (axioms, inductives, etc.): Not included as source nodes

Parameters:
- `includeAux`: If `false`, filter out auxiliary declarations
- `includeInstances`: If `false`, filter out typeclass instances
-/
public def proofDepsGraph (env : Environment) 
    (includeAux : Bool := false) (includeInstances : Bool := false) : CoreM (NameMap (Array Name)) := do
  let mut graph : NameMap (Array Name) := {}
  let mut processedCount := 0
  
  for (name, info) in env.constants.toList do
    let shouldInclude ← shouldIncludeConstant env name includeAux includeInstances
    if !shouldInclude then continue
    
    match info with
    | .thmInfo val =>
      let deps := val.value.getUsedConstants
      -- Process dependencies in smaller chunks to avoid stack buildup
      let processedDeps ← applyTransitiveClosureChunked env deps includeAux includeInstances
      graph := graph.insert name processedDeps
      
    | .defnInfo val =>
      let deps := val.value.getUsedConstants
      -- Process dependencies in smaller chunks to avoid stack buildup  
      let processedDeps ← applyTransitiveClosureChunked env deps includeAux includeInstances
      graph := graph.insert name processedDeps
      
    | .recInfo _ | .axiomInfo _ | .inductInfo _ | .ctorInfo _ | .opaqueInfo _ | .quotInfo _ =>
      continue
    
    processedCount := processedCount + 1
    -- Progress indicator and yield opportunity
    if processedCount % 1000 == 0 then
      IO.eprintln s!"Processed {processedCount} constants..."
  
  return graph

end Lean.Environment
