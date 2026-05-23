/-
Copyright (c) 2024 LeanGraph Contributors. All rights reserved.
Modifications (c) 2026 Evan Wang. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: LeanGraph Contributors
-/
module

public import LeanGraph.Graph.Unified
public import LeanGraph.Types
open Lean
open LeanGraph.Unified
open LeanGraph.Types

/-!
# Unified Graph DOT Export

Export unified dependency graphs to DOT format with node metadata in CSV.

Combines DOT visualization with metadata (declaration type, module) in a
companion CSV file for analysis and visualization tools.
-/

namespace LeanGraph.Unified.Export

private def computeInDegrees (g : UnifiedGraph) : NameMap Nat :=
  let addTargets (acc : NameMap Nat) (targets : Array Name) : NameMap Nat :=
    targets.foldl (fun a t => a.insert t ((a.find? t |>.getD 0) + 1)) acc
  let addSigTargets (acc : NameMap Nat) (targets : Array (Name × SigEdgeMeta)) : NameMap Nat :=
    targets.foldl (fun a (t, _) => a.insert t ((a.find? t |>.getD 0) + 1)) acc
  let step (acc : NameMap Nat) (m : NameMap (Array Name)) : NameMap Nat :=
    m.foldl (fun a _ targets => addTargets a targets) acc
  let stepSig (acc : NameMap Nat) (m : NameMap (Array (Name × SigEdgeMeta))) : NameMap Nat :=
    m.foldl (fun a _ targets => addSigTargets a targets) acc
  step (step (step (stepSig (step (step {} g.extendsEdges) g.fieldEdges)
    g.signatureEdges) g.proofEdges) g.defEdges) g.docRefEdges

private def csvEscape (s : String) : String :=
  s.replace "\n" " " |>.replace "\r" " " |>.replace "\"" "\"\""

/-- Write companion nodes CSV: name,decl_type,module,in_degree,docstring -/
private def writeNodesCSV (g : UnifiedGraph) (csvPath : String) : IO Unit := do
  IO.eprintln s!"[Unified] Writing nodes CSV to {csvPath}"
  let csv ← IO.FS.Handle.mk ⟨csvPath⟩ IO.FS.Mode.write
  let inDegrees := computeInDegrees g
  csv.putStrLn "name,decl_type,module,in_degree,is_instance,is_tactic_object,docstring"
  for (name, declType) in g.nodeTypes.toList do
    let modName := (g.nodeModules.find? name |>.getD .anonymous).toString
    let deg := inDegrees.find? name |>.getD 0
    let isInst := if g.nodeInstances.contains name then "true" else "false"
    let isTac  := if g.nodeTacticObjects.contains name then "true" else "false"
    let doc := csvEscape (g.nodeDocstrings.find? name |>.getD "")
    csv.putStrLn s!"\"{name}\",\"{declType.label}\",\"{modName}\",{deg},{isInst},{isTac},\"{doc}\""

/-- Write unified graph to DOT format with categorized edges -/
public def writeUnifiedGraphToFile
    (g : UnifiedGraph)
    (filePath : System.FilePath)
    (allowedEdgeTypes : Option (Std.HashSet String) := none) : IO Unit := do
  let allow (label : String) : Bool :=
    match allowedEdgeTypes with
    | none => true
    | some s => s.contains label

  IO.eprintln s!"[Unified] Writing unified graph to {filePath}"

  -- Write companion nodes CSV alongside the DOT file
  let dotStr := filePath.toString
  let csvStr := if dotStr.endsWith ".dot"
                then (dotStr.dropEnd 4).toString ++ "_nodes.csv"
                else dotStr ++ "_nodes.csv"
  writeNodesCSV g csvStr

  let handle ← IO.FS.Handle.mk filePath IO.FS.Mode.write

  -- Write header
  handle.putStrLn "digraph unified_graph {"

  -- Write nodes
  IO.eprintln "[Unified DOT] Writing nodes..."
  for (name, _) in g.nodeTypes.toList do
    handle.putStrLn s!"  \"{name}\";"

  -- Write extends edges
  if allow "extends" then
    IO.eprintln "[Unified DOT] Writing extends edges..."
    for (source, targets) in g.extendsEdges.toList do
      for target in targets do
        handle.putStrLn s!"  \"{target}\" -> \"{source}\" [kind=extends];"

  -- Write field edges
  if allow "field" then
    IO.eprintln "[Unified DOT] Writing field edges..."
    for (source, targets) in g.fieldEdges.toList do
      for target in targets do
        handle.putStrLn s!"  \"{target}\" -> \"{source}\" [kind=field];"

  -- Write signature edges
  if allow "sig" then
    IO.eprintln "[Unified DOT] Writing signature edges..."
    for (source, targets) in g.signatureEdges.toList do
      for (target, em) in targets do
        let attrs := s!"kind=sig, pos={em.position.label}, bi={em.binderKind.label}, role={em.appRole.label}"
        handle.putStrLn s!"  \"{target}\" -> \"{source}\" [{attrs}];"

  -- Write proof edges
  if allow "proof" then
    IO.eprintln "[Unified DOT] Writing proof edges..."
    for (source, targets) in g.proofEdges.toList do
      for target in targets do
        handle.putStrLn s!"  \"{target}\" -> \"{source}\" [kind=proof];"

  -- Write def edges
  if allow "def" then
    IO.eprintln "[Unified DOT] Writing def edges..."
    for (source, targets) in g.defEdges.toList do
      for target in targets do
        handle.putStrLn s!"  \"{target}\" -> \"{source}\" [kind=def];"

  -- Write docref edges
  if allow "docref" then
    IO.eprintln "[Unified DOT] Writing docref edges..."
    for (source, targets) in g.docRefEdges.toList do
      for target in targets do
        handle.putStrLn s!"  \"{target}\" -> \"{source}\" [kind=docref];"

  -- Write footer
  handle.putStrLn "}"
  _ ← handle.flush

  -- Statistics
  let totalEdges := UnifiedGraph.totalEdgeCount g
  IO.eprintln s!"[Unified] Wrote {g.nodes.toList.length} nodes and {totalEdges} edges"
  IO.eprintln s!"[Unified] Edge breakdown:"
  IO.eprintln s!"  - Extends:   {UnifiedGraph.edgeCountByType g .extends}"
  IO.eprintln s!"  - Field:     {UnifiedGraph.edgeCountByType g .field}"
  IO.eprintln s!"  - Signature: {UnifiedGraph.edgeCountByType g .signatureType}"
  IO.eprintln s!"  - Proof:     {UnifiedGraph.edgeCountByType g .proofCall}"
  IO.eprintln s!"  - Def:       {UnifiedGraph.edgeCountByType g .defCall}"
  IO.eprintln s!"  - DocRef:    {UnifiedGraph.edgeCountByType g .docRef}"

end LeanGraph.Unified.Export
