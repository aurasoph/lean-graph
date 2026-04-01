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
  
  for (name, info) in env.constants.toList do
    let shouldInclude ← shouldIncludeConstant env name includeAux includeInstances
    if !shouldInclude then continue
    
    match info with
    | .thmInfo val =>
      let deps := val.value.getUsedConstants
      let processedDeps ← applyTransitiveClosure env deps includeAux includeInstances
      graph := graph.insert name processedDeps
      
    | .defnInfo val =>
      let deps := val.value.getUsedConstants
      let processedDeps ← applyTransitiveClosure env deps includeAux includeInstances
      graph := graph.insert name processedDeps
      
    | .recInfo _ | .axiomInfo _ | .inductInfo _ | .ctorInfo _ | .opaqueInfo _ | .quotInfo _ =>
      continue
  
  return graph

end Lean.Environment
