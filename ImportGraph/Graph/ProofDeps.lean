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

-- Process dependency arrays without accumulating in large intermediate arrays
private def applyTransitiveClosureChunked (env : Environment) (deps : Array Name) 
    (includeAux : Bool) (includeInstances : Bool) : CoreM (Array Name) := do
  let mut result : Array Name := #[]
  let mut seen : NameSet := {}
  
  let depsCount := deps.size
  let mut totalProcessed := 0
  
  -- Process all dependencies, but don't keep large intermediate collections
  for i in List.range depsCount do
    let dep := deps[i]!
    totalProcessed := totalProcessed + 1
    
    if totalProcessed % 50000 == 0 then
      IO.eprintln s!"[DEBUG-CHUNKED] Processed {totalProcessed}/{depsCount} dependencies"
    
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

-- Stream proof-deps graph directly to file handle without accumulating entire graph in memory
public def proofDepsGraphStreaming (env : Environment) 
    (handle : IO.FS.Handle)
    (includeAux : Bool := false) (includeInstances : Bool := false) : CoreM Unit := do
  let mut processedCount := 0
  let mut skippedCount := 0
  let mut edgeCount := 0
  let allConstants := env.constants.toList
  let totalCount := allConstants.length
  
  IO.eprintln "Starting proof-deps graph generation (streaming)..."
  
  for (name, info) in allConstants do
    processedCount := processedCount + 1
    
    -- Print progress every 5000 constants
    if processedCount % 5000 == 0 then
      IO.eprintln s!"Processing constant {processedCount}/{totalCount}: {name}"
    
    let shouldInclude ← shouldIncludeConstant env name includeAux includeInstances
    if !shouldInclude then 
      skippedCount := skippedCount + 1
      continue
    
    let deps : Array Name := match info with
      | .thmInfo val => val.value.getUsedConstants
      | .defnInfo val => val.value.getUsedConstants
      | _ => #[]
    
    if deps.isEmpty then continue
    
    let processedDeps ← applyTransitiveClosureChunked env deps includeAux includeInstances
    
    -- Write edges directly to file as we discover them
    for dep in processedDeps do
      handle.putStrLn s!"  \"{dep}\" -> \"{name}\";"
      edgeCount := edgeCount + 1
      
      -- Flush every 1000 edges
      if edgeCount % 1000 == 0 then
        _ ← handle.flush
  
  IO.eprintln s!"Completed: {processedCount} constants iterated, {skippedCount} skipped, {edgeCount} edges written"

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
  let mut skippedCount := 0
  
  IO.eprintln "Starting proof-deps graph generation..."
  
  for (name, info) in env.constants.toList do
    processedCount := processedCount + 1
    
    -- Print progress every 5000 constants
    if processedCount % 5000 == 0 then
      IO.eprintln s!"Processing constant {processedCount}: {name}"
    
    let shouldInclude ← shouldIncludeConstant env name includeAux includeInstances
    if !shouldInclude then 
      skippedCount := skippedCount + 1
      continue
    
    match info with
    | .thmInfo val =>
      let deps := val.value.getUsedConstants
      let processedDeps ← applyTransitiveClosureChunked env deps includeAux includeInstances
      if processedDeps.size > 0 then
        graph := graph.insert name processedDeps
      
    | .defnInfo val =>
      let deps := val.value.getUsedConstants
      let processedDeps ← applyTransitiveClosureChunked env deps includeAux includeInstances
      if processedDeps.size > 0 then
        graph := graph.insert name processedDeps
      
    | .recInfo _ | .axiomInfo _ | .inductInfo _ | .ctorInfo _ | .opaqueInfo _ | .quotInfo _ =>
      continue
  
  IO.eprintln s!"Completed: {processedCount} constants iterated, {skippedCount} skipped"
  return graph

end Lean.Environment
