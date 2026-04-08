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
import Lean.Structure

open Lean Meta

/-!
# Type Dependency Graph (Blueprint Mode)

This module constructs a dependency graph based on type signatures.
For each constant, we extract all constants mentioned in its type signature.

Provides tiered filtering via `FilterTier`.
-/

namespace Lean.Environment

/-- 
Extract type dependencies: all constants mentioned in the type signature.
-/
private def getTypeDependencies (_env : Environment) (_name : Name) (info : ConstantInfo) : Array Name :=
  info.type.getUsedConstants

/-- Build type dependency graph based on constant type signatures. -/
public def typeDepsGraph (env : Environment) 
    (tier : FilterTier := .standard) (includeInstances : Bool := false) :
    CoreM (NameMap (Array Name)) := do
  let mut graph : NameMap (Array Name) := {}
  
  for (name, info) in env.constants.toList do
    let shouldInclude ← shouldIncludeConstant env name tier includeInstances
    if shouldInclude then
      let deps := getTypeDependencies env name info
      let processedDeps ← applyTransitiveClosure env deps tier includeInstances
      graph := graph.insert name processedDeps
  
  return graph

end Lean.Environment
