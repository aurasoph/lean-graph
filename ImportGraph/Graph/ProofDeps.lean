/-
Copyright (c) 2024 ImportGraph Contributors. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: ImportGraph Contributors
-/
module

public import Lean.Environment
public import Lean.CoreM
public import ImportGraph.Graph.FilterCommon
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

-- Process dependency arrays for proof-deps specifically
private def applyTransitiveClosureChunked (env : Environment) (deps : Array Name) 
    (tier : FilterTier := .standard) (includeInstances : Bool := false) : CoreM (Array Name) := do
  applyTransitiveClosureForProofDeps env deps tier includeInstances

-- Stream proof-deps graph directly to file handle
public def proofDepsGraphStreaming (env : Environment) 
    (handle : IO.FS.Handle)
    (tier : FilterTier := .standard) (includeInstances : Bool := false) : CoreM Unit := do
  let mut processedCount := 0
  let mut skippedCount := 0
  let mut edgeCount := 0
  let mut isolatedNodes := 0
  let allConstants := env.constants.toList
  let totalCount := allConstants.length
  
  IO.eprintln "Starting proof-deps graph generation (streaming)..."
  
  for (name, info) in allConstants do
    processedCount := processedCount + 1
    
    if processedCount % 5000 == 0 then
      IO.eprintln s!"Processing constant {processedCount}/{totalCount}: {name}"
    
    let shouldInclude ← shouldIncludeConstantInProofDeps env name tier includeInstances
    if !shouldInclude then 
      skippedCount := skippedCount + 1
      continue
    
    let deps : Array Name := match info with
      | .thmInfo val => val.value.getUsedConstants
      | .defnInfo val => val.value.getUsedConstants
      | .axiomInfo _ => #[]
      | _ => #[]
    
    let processedDeps ← applyTransitiveClosureForProofDeps env deps tier includeInstances
    
    if processedDeps.isEmpty then
      handle.putStrLn s!"  \"{name}\";"
      isolatedNodes := isolatedNodes + 1
    else
      for dep in processedDeps do
        handle.putStrLn s!"  \"{dep}\" -> \"{name}\";"
        edgeCount := edgeCount + 1
      
      if edgeCount % 1000 == 0 then
        _ ← handle.flush
  
  IO.eprintln s!"Completed: {processedCount} constants iterated, {skippedCount} skipped, {edgeCount} edges, {isolatedNodes} isolated nodes"

/--
Build a proof dependencies graph from the Lean environment.
-/
public def proofDepsGraph (env : Environment) 
    (tier : FilterTier := .standard) (includeInstances : Bool := false) : CoreM (NameMap (Array Name)) := do
  let mut graph : NameMap (Array Name) := {}
  let mut processedCount := 0
  let mut skippedCount := 0
  
  IO.eprintln "Starting proof-deps graph generation..."
  
  for (name, info) in env.constants.toList do
    processedCount := processedCount + 1
    
    if processedCount % 5000 == 0 then
      IO.eprintln s!"Processing constant {processedCount}: {name}"
    
    let shouldInclude ← shouldIncludeConstantInProofDeps env name tier includeInstances
    if !shouldInclude then 
      skippedCount := skippedCount + 1
      continue
    
    match info with
    | .thmInfo val | .defnInfo val =>
      let deps := val.value.getUsedConstants
      let processedDeps ← applyTransitiveClosureForProofDeps env deps tier includeInstances
      graph := graph.insert name processedDeps
      
    | .axiomInfo _ =>
      graph := graph.insert name #[]
      
    | _ =>
      continue
  
  IO.eprintln s!"Completed: {processedCount} constants iterated, {skippedCount} skipped"
  return graph

end Lean.Environment
