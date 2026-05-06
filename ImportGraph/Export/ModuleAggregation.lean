/-
Copyright (c) 2026 Evan Wang. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Evan Wang
-/

import ImportGraph.Graph.Unified
import ImportGraph.Types
import Lean.Data.NameMap.Basic
open Lean
open ImportGraph.Unified
open ImportGraph.Types

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

namespace ImportGraph.Unified.Aggregation

/-- Module dependency graph: map from module to set of modules it depends on -/
public structure ModuleGraph where
  nodes : Std.HashSet Name
  edges : NameMap (Std.HashSet Name)
  edgeCounts : NameMap (NameMap Nat)

/-- Build module-level graph by aggregating declaration dependencies -/
def buildModuleGraph (g : UnifiedGraph) : ModuleGraph :=
  -- Collect all modules
  let nodes : Std.HashSet Name :=
    g.nodeModules.foldl (fun acc _ modName =>
      acc.insert modName) {}

  -- Gather all edges from all edge types
  let allEdges : List (Name × Name) :=
    (g.extendsEdges.toList.flatMap fun (src, targets) =>
      targets.toList.map fun tgt => (tgt, src)) ++
    (g.fieldEdges.toList.flatMap fun (src, targets) =>
      targets.toList.map fun tgt => (tgt, src)) ++
    (g.signatureEdges.toList.flatMap fun (src, targets) =>
      targets.toList.map fun tgt => (tgt, src)) ++
    (g.proofEdges.toList.flatMap fun (src, targets) =>
      targets.toList.map fun tgt => (tgt, src)) ++
    (g.defEdges.toList.flatMap fun (src, targets) =>
      targets.toList.map fun tgt => (tgt, src)) ++
    (g.docRefEdges.toList.flatMap fun (src, targets) =>
      targets.toList.map fun tgt => (tgt, src))

  -- Aggregate edges and counts
  let (edges, edgeCounts) :=
    allEdges.foldl (fun (acc : NameMap (Std.HashSet Name) × NameMap (NameMap Nat)) (edge : Name × Name) =>
      let (edgeAcc, countAcc) := acc
      let (sourceDecl, targetDecl) := edge
      let sourceModule := g.nodeModules.find? sourceDecl |>.getD Name.anonymous
      let targetModule := g.nodeModules.find? targetDecl |>.getD Name.anonymous

      if sourceModule != targetModule && sourceModule != Name.anonymous && targetModule != Name.anonymous then
        -- Add to edges set
        let currentDeps := edgeAcc.find? sourceModule |>.getD {}
        let newEdgeAcc := edgeAcc.insert sourceModule (currentDeps.insert targetModule)

        -- Count edges between these modules
        let currentCounts := countAcc.find? sourceModule |>.getD {}
        let count := currentCounts.find? targetModule |>.getD 0
        let newCounts := currentCounts.insert targetModule (count + 1)
        let newCountAcc := countAcc.insert sourceModule newCounts

        (newEdgeAcc, newCountAcc)
      else
        (edgeAcc, countAcc)
    ) ({}, {})

  { nodes, edges, edgeCounts }

/-- Write module-level aggregated graph to CSV format -/
def writeModuleGraphToCSV (mg : ModuleGraph) (filePath : System.FilePath) : IO Unit := do
  IO.eprintln s!"[Module Aggregation] Writing module graph to {filePath}"

  -- Write nodes CSV
  let fpStr := filePath.toString
  let nodesPath : String := if fpStr.endsWith ".csv"
                            then (fpStr.dropEnd 4).toString ++ "_nodes.csv"
                            else fpStr ++ "_nodes.csv"

  let nodesHandle ← IO.FS.Handle.mk nodesPath IO.FS.Mode.write
  nodesHandle.putStrLn "module"
  let nodeList : List Name := mg.nodes.toList
  for module in nodeList do
    nodesHandle.putStrLn s!"\"{module}\""
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
def writeModuleGraphToDot (mg : ModuleGraph) (filePath : System.FilePath) : IO Unit := do
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

end ImportGraph.Unified.Aggregation
