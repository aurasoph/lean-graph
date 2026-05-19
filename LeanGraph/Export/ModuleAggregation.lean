/-
Copyright (c) 2026 Evan Wang. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Evan Wang
-/
module

public import LeanGraph.Graph.Unified
public import LeanGraph.Types
import Lean.Data.NameMap.Basic
open Lean
open LeanGraph.Unified
open LeanGraph.Types

/-!
# Module-Level Graph Aggregation

Aggregate declaration-level dependencies to module level.
Answers architectural questions: "Which modules depend on which modules?"

Each node in the aggregated graph represents a module (file), and edges represent
dependencies between modules based on declaration-level dependencies.

This provides a simpler view of the codebase structure, useful for:
- Understanding file-level dependencies
- Identifying bottleneck modules
- Planning refactoring strategies
- Visualizing architectural boundaries
-/

namespace LeanGraph.Unified.Aggregation

/-- Module dependency graph: map from module to set of modules it depends on -/
public structure ModuleGraph where
  nodes : Std.HashSet Name
  edges : NameMap (Std.HashSet Name)
  edgeCounts : NameMap (NameMap Nat)
  totalOutEdges : NameMap Nat  -- outgoing decl-edges per module (includes intra)
  intraEdges : NameMap Nat     -- intra-module decl-edges per module
  declCounts : NameMap Nat
  utilization : NameMap (NameMap (Std.HashSet Name))  -- srcMod → tgtMod → referencing decls

/-- Build module-level graph by aggregating declaration dependencies -/
public def buildModuleGraph (g : UnifiedGraph) : ModuleGraph :=
  let nodes : Std.HashSet Name :=
    g.nodeModules.foldl (fun acc _ modName => acc.insert modName) {}

  let declCounts : NameMap Nat :=
    g.nodeModules.foldl (fun acc _ modName =>
      acc.insert modName ((acc.find? modName |>.getD 0) + 1)) {}

  let allEdges : List (Name × Name) :=
    (g.extendsEdges.toList.flatMap fun (src, targets) =>
      targets.toList.map fun tgt => (src, tgt)) ++
    (g.fieldEdges.toList.flatMap fun (src, targets) =>
      targets.toList.map fun tgt => (src, tgt)) ++
    (g.signatureEdges.toList.flatMap fun (src, targets) =>
      targets.toList.map fun (tgt, _) => (src, tgt)) ++
    (g.proofEdges.toList.flatMap fun (src, targets) =>
      targets.toList.map fun tgt => (src, tgt)) ++
    (g.defEdges.toList.flatMap fun (src, targets) =>
      targets.toList.map fun tgt => (src, tgt)) ++
    (g.docRefEdges.toList.flatMap fun (src, targets) =>
      targets.toList.map fun tgt => (src, tgt))

  let init : NameMap (Std.HashSet Name) × NameMap (NameMap Nat) ×
             NameMap Nat × NameMap Nat × NameMap (NameMap (Std.HashSet Name)) :=
    ({}, {}, {}, {}, {})

  let (edges, edgeCounts, totalOutEdges, intraEdges, utilization) :=
    allEdges.foldl (fun acc (srcDecl, tgtDecl) =>
      let (edgeAcc, countAcc, totalAcc, intraAcc, utilAcc) := acc
      let srcMod := g.nodeModules.find? srcDecl |>.getD Name.anonymous
      let tgtMod := g.nodeModules.find? tgtDecl |>.getD Name.anonymous
      if srcMod == Name.anonymous || tgtMod == Name.anonymous then acc
      else
        let totalAcc' := totalAcc.insert srcMod ((totalAcc.find? srcMod |>.getD 0) + 1)
        if srcMod == tgtMod then
          let intraAcc' := intraAcc.insert srcMod ((intraAcc.find? srcMod |>.getD 0) + 1)
          (edgeAcc, countAcc, totalAcc', intraAcc', utilAcc)
        else
          let currentDeps := edgeAcc.find? srcMod |>.getD {}
          let edgeAcc' := edgeAcc.insert srcMod (currentDeps.insert tgtMod)
          let currentCounts := countAcc.find? srcMod |>.getD {}
          let count := currentCounts.find? tgtMod |>.getD 0
          let countAcc' := countAcc.insert srcMod (currentCounts.insert tgtMod (count + 1))
          let srcModUtil := utilAcc.find? srcMod |>.getD {}
          let tgtSet := srcModUtil.find? tgtMod |>.getD {}
          let utilAcc' := utilAcc.insert srcMod (srcModUtil.insert tgtMod (tgtSet.insert srcDecl))
          (edgeAcc', countAcc', totalAcc', intraAcc, utilAcc')
    ) init

  { nodes, edges, edgeCounts, totalOutEdges, intraEdges, declCounts, utilization }

/-- Compute median of a list of floats (returns 0.0 for empty list) -/
private def median (xs : List Float) : Float :=
  if xs.isEmpty then 0.0
  else
    let sorted := xs.mergeSort (· < ·)
    let n := sorted.length
    if n % 2 == 1 then
      sorted[n / 2]!
    else
      (sorted[n / 2 - 1]! + sorted[n / 2]!) / 2.0

private def moduleCohesion (mg : ModuleGraph) (modName : Name) : Float :=
  let total := mg.totalOutEdges.find? modName |>.getD 0
  if total == 0 then 0.0
  else
    let intra := mg.intraEdges.find? modName |>.getD 0
    Float.ofNat intra / Float.ofNat total

private def moduleImportUtilizationMedian (mg : ModuleGraph) (modName : Name) : Float :=
  let srcUtil := mg.utilization.find? modName |>.getD {}
  let ratios : List Float := srcUtil.toList.filterMap fun (tgtMod, srcDecls) =>
    let tgtTotal := mg.declCounts.find? tgtMod |>.getD 0
    if tgtTotal == 0 then none
    else some (Float.ofNat srcDecls.toList.length / Float.ofNat tgtTotal)
  median ratios

/-- Write module-level aggregated graph to CSV format -/
public def writeModuleGraphToCSV (mg : ModuleGraph) (filePath : System.FilePath) : IO Unit := do
  IO.eprintln s!"[Module Aggregation] Writing module graph to {filePath}"

  let fpStr := filePath.toString
  let nodesPath : String := if fpStr.endsWith ".csv"
                            then (fpStr.dropEnd 4).toString ++ "_nodes.csv"
                            else fpStr ++ "_nodes.csv"

  let nodesHandle ← IO.FS.Handle.mk nodesPath IO.FS.Mode.write
  nodesHandle.putStrLn "module,cohesion,import_utilization_median"
  let nodeList : List Name := mg.nodes.toList
  for modName in nodeList do
    let cohesion := moduleCohesion mg modName
    let utilMed := moduleImportUtilizationMedian mg modName
    nodesHandle.putStrLn s!"\"{modName}\",{cohesion},{utilMed}"
  _ ← nodesHandle.flush

  -- Write edges CSV
  let edgesPath := if filePath.toString.endsWith ".csv"
                   then ((filePath.toString.take (filePath.toString.length - 4)).toString ++ "_edges.csv" : String)
                   else (filePath.toString ++ "_edges.csv" : String)

  let edgesHandle ← IO.FS.Handle.mk edgesPath IO.FS.Mode.write
  edgesHandle.putStrLn "source,target,weight"
  let edgesList : List (Name × Std.HashSet Name) := mg.edges.toList
  for (sourceModule, targetModules) in edgesList do
    let targetModulesList : List Name := targetModules.toList
    for targetModule in targetModulesList do
      let weight : Nat :=
        match mg.edgeCounts.find? sourceModule with
        | some counts =>
          match counts.find? targetModule with
          | some w => w
          | none => 0
        | none => 0
      edgesHandle.putStrLn s!"\"{sourceModule}\",\"{targetModule}\",{weight}"
  _ ← edgesHandle.flush

  -- Statistics
  let totalEdges := mg.edges.foldl (fun acc _ targets => acc + targets.toList.length) 0
  IO.eprintln s!"[Module Aggregation] Wrote {mg.nodes.toList.length} modules and {totalEdges} inter-module edges"
  IO.eprintln s!"[Module Aggregation] Nodes file: {nodesPath}"
  IO.eprintln s!"[Module Aggregation] Edges file: {edgesPath}"

/-- Write module-level aggregated graph to DOT format -/
public def writeModuleGraphToDot (mg : ModuleGraph) (filePath : System.FilePath) : IO Unit := do
  IO.eprintln s!"[Module Aggregation] Writing module graph to {filePath}"

  let handle ← IO.FS.Handle.mk filePath IO.FS.Mode.write

  handle.putStrLn "digraph module_graph {"
  handle.putStrLn "  rankdir=LR;"
  handle.putStrLn "  node [shape=box, style=rounded];"

  -- Write nodes
  let nodeList : List Name := mg.nodes.toList
  for module in nodeList do
    handle.putStrLn s!"  \"{module}\";"

  -- Write edges with weight labels
  let edgesList : List (Name × Std.HashSet Name) := mg.edges.toList
  for (sourceModule, targetModules) in edgesList do
    let targetModulesList : List Name := targetModules.toList
    for targetModule in targetModulesList do
      let weight : Nat :=
        match mg.edgeCounts.find? sourceModule with
        | some counts =>
          match counts.find? targetModule with
          | some w => w
          | none => 0
        | none => 0
      handle.putStrLn s!"  \"{sourceModule}\" -> \"{targetModule}\" [label=\"{weight}\"];"

  handle.putStrLn "}"
  _ ← handle.flush

  let totalEdges := mg.edges.foldl (fun acc _ targets => acc + targets.toList.length) 0
  IO.eprintln s!"[Module Aggregation] Wrote {mg.nodes.toList.length} modules and {totalEdges} inter-module edges"

end LeanGraph.Unified.Aggregation
