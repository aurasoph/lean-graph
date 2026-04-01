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
# Type Dependency Graph (Blueprint Mode)

This module constructs a dependency graph based on type signatures.
For each constant, we extract all constants mentioned in its type signature.

This is useful for understanding the "blueprint" of dependencies - what types
are needed to even state a theorem or definition, independent of its proof.

## Instance Filtering (Default: ON)

By default, typeclass instances are filtered out unless `--include-instances` is used.
Instances create "star patterns" and are mechanically derived from type definitions.
Use `--include-instances` to restore instance nodes.
-/

namespace Lean.Environment

/-- Extract type dependencies: all constants mentioned in the type signature. -/
private def getTypeDependencies (info : ConstantInfo) : Array Name :=
  info.type.getUsedConstants

/-- Build type dependency graph based on constant type signatures. -/
public def typeDepsGraph (env : Environment) 
    (includeAux : Bool := false) (includeInstances : Bool := false) :
    CoreM (NameMap (Array Name)) := do
  let mut graph : NameMap (Array Name) := {}
  
  for (name, info) in env.constants.toList do
    let shouldInclude ← shouldIncludeConstant env name includeAux includeInstances
    if shouldInclude then
      let deps := getTypeDependencies info
      let processedDeps ← applyTransitiveClosure env deps includeAux includeInstances
      graph := graph.insert name processedDeps
  
  return graph

end Lean.Environment
