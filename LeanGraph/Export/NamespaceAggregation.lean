/-
Copyright (c) 2026 Evan Wang. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Evan Wang
-/
module

public import LeanGraph.Export.ModuleAggregation
open Lean
open LeanGraph.Unified
open LeanGraph.Unified.Aggregation

/-!
# Namespace-Level Graph Aggregation

Groups modules by their depth-2 Lean name prefix (`Mathlib.Algebra`, `Init.Data`, etc.).
Names with fewer than 2 components are used as-is.
-/

namespace LeanGraph.Unified.NamespaceAggregation

/-- Namespace-level dependency graph -/
public structure NamespaceGraph where
  nodes : Std.HashSet Name
  nodeModuleCounts : NameMap Nat
  nodeDeclCounts : NameMap Nat
  edges : NameMap (NameMap Nat)  -- source_ns → target_ns → weight

private def namespaceOf (modName : Name) : Name :=
  let parts := modName.toString.splitOn "."
  match parts with
  | [] => .anonymous
  | [a] => .str .anonymous a
  | a :: b :: _ => .str (.str .anonymous a) b

public def buildNamespaceGraph (mg : ModuleGraph) : NamespaceGraph :=
  let modList := mg.nodes.toList
  let modToNs : NameMap Name :=
    modList.foldl (fun acc modName => acc.insert modName (namespaceOf modName)) {}

  let nsModCounts : NameMap Nat :=
    modList.foldl (fun acc modName =>
      let ns := modToNs.find? modName |>.getD Name.anonymous
      acc.insert ns ((acc.find? ns |>.getD 0) + 1)
    ) {}

  let nsDeclCounts : NameMap Nat :=
    modList.foldl (fun acc modName =>
      let ns := modToNs.find? modName |>.getD Name.anonymous
      let declsInMod := mg.declCounts.find? modName |>.getD 0
      acc.insert ns ((acc.find? ns |>.getD 0) + declsInMod)
    ) {}

  let nodes : Std.HashSet Name :=
    nsModCounts.foldl (fun (acc : Std.HashSet Name) ns _ => acc.insert ns) {}

  let foldTgtCounts (acc : NameMap (NameMap Nat)) (srcNs : Name) (tgtCounts : NameMap Nat) :
      NameMap (NameMap Nat) :=
    tgtCounts.foldl (fun acc2 tgtMod weight =>
      let tgtNs := modToNs.find? tgtMod |>.getD Name.anonymous
      if srcNs == Name.anonymous || tgtNs == Name.anonymous then acc2
      else
        let srcRow : NameMap Nat := acc2.find? srcNs |>.getD {}
        let prev := srcRow.find? tgtNs |>.getD 0
        acc2.insert srcNs (srcRow.insert tgtNs (prev + weight))
    ) acc

  let nsEdges : NameMap (NameMap Nat) :=
    mg.edgeCounts.foldl (fun acc srcMod tgtCounts =>
      let srcNs := modToNs.find? srcMod |>.getD Name.anonymous
      foldTgtCounts acc srcNs tgtCounts
    ) {}

  { nodes, nodeModuleCounts := nsModCounts, nodeDeclCounts := nsDeclCounts, edges := nsEdges }

public def writeNamespaceGraph (ng : NamespaceGraph) (basePath : String) : IO Unit := do
  let nodesPath := basePath ++ "_namespace_nodes.csv"
  IO.eprintln s!"[Namespace Aggregation] Writing namespace nodes to {nodesPath}"
  let nodesHandle ← IO.FS.Handle.mk nodesPath IO.FS.Mode.write
  nodesHandle.putStrLn "namespace,module_count,declaration_count"
  for ns in ng.nodes.toList do
    let mc := ng.nodeModuleCounts.find? ns |>.getD 0
    let dc := ng.nodeDeclCounts.find? ns |>.getD 0
    nodesHandle.putStrLn s!"\"{ns}\",{mc},{dc}"
  _ ← nodesHandle.flush

  let edgesPath := basePath ++ "_namespace_edges.csv"
  IO.eprintln s!"[Namespace Aggregation] Writing namespace edges to {edgesPath}"
  let edgesHandle ← IO.FS.Handle.mk edgesPath IO.FS.Mode.write
  edgesHandle.putStrLn "source,target,weight"
  for (srcNs, tgtCounts) in ng.edges.toList do
    for (tgtNs, weight) in tgtCounts.toList do
      edgesHandle.putStrLn s!"\"{srcNs}\",\"{tgtNs}\",{weight}"
  _ ← edgesHandle.flush

  let totalEdges := ng.edges.foldl (fun acc _ m => acc + m.toList.length) 0
  IO.eprintln s!"[Namespace Aggregation] Wrote {ng.nodes.toList.length} namespaces and {totalEdges} edges"

end LeanGraph.Unified.NamespaceAggregation
