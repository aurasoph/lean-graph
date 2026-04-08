/-
Copyright (c) 2024 ImportGraph Contributors. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: ImportGraph Contributors
-/
module

public import ImportGraph.Graph.Unified
open Lean
open ImportGraph.Unified

namespace ImportGraph.Unified.Export

/-- Write unified graph to DOT format with categorized edges -/
public def writeUnifiedGraphToFile 
    (g : UnifiedGraph)
    (filePath : System.FilePath) : IO Unit := do
  
  IO.eprintln s!"[Unified] Writing unified graph to {filePath}"
  
  let handle ← IO.FS.Handle.mk filePath IO.FS.Mode.write
  
  -- Write header
  handle.putStrLn "digraph unified_graph {"
  
  -- Write nodes
  IO.eprintln "[Unified DOT] Writing nodes..."
  for (name, declType) in g.nodeTypes.toList do
    let shape := declType.shape
    let fillColor := declType.fillColor
    handle.putStrLn s!"  \"{name}\" [shape={shape}, style=filled, fillcolor=\"{fillColor}\"];"
  
  -- Write extends edges (blue)
  IO.eprintln "[Unified DOT] Writing extends edges..."
  for (source, targets) in g.extendsEdges.toList do
    for target in targets do
      handle.putStrLn s!"  \"{target}\" -> \"{source}\" [color=\"blue\", penwidth=3];"
  
  -- Write field edges (cyan)
  IO.eprintln "[Unified DOT] Writing field edges..."
  for (source, targets) in g.fieldEdges.toList do
    for target in targets do
      handle.putStrLn s!"  \"{target}\" -> \"{source}\" [color=\"cyan\", penwidth=2];"
  
  -- Write signature edges (orange)
  IO.eprintln "[Unified DOT] Writing signature edges..."
  for (source, targets) in g.signatureEdges.toList do
    for target in targets do
      handle.putStrLn s!"  \"{target}\" -> \"{source}\" [color=\"orange\", penwidth=1, style=dashed];"
  
  -- Write proof edges (green)
  IO.eprintln "[Unified DOT] Writing proof edges..."
  for (source, targets) in g.proofEdges.toList do
    for target in targets do
      handle.putStrLn s!"  \"{target}\" -> \"{source}\" [color=\"green\", penwidth=3];"
  
  -- Write def edges (lime)
  IO.eprintln "[Unified DOT] Writing def edges..."
  for (source, targets) in g.defEdges.toList do
    for target in targets do
      handle.putStrLn s!"  \"{target}\" -> \"{source}\" [color=\"#32CD32\", penwidth=2];"
  
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

end ImportGraph.Unified.Export
