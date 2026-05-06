/-
Copyright (c) 2026 Evan Wang. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Evan Wang
-/
module

public import ImportGraph.Graph.Unified
public import ImportGraph.Types
import Lean.Data.Json
open Lean
open ImportGraph.Unified
open ImportGraph.Types

/-!
# Unified Graph NDJSON Export

Export unified dependency graphs to NDJSON format (newline-delimited JSON).
Each line is a JSON object representing a declaration with its edges.

Format:
```json
{
  "name": "Nat.add",
  "decl_type": "def",
  "module": "Init.Data.Nat.Basic",
  "edges": [
    {"target": "Nat", "kind": "sig"},
    {"target": "Nat.add_eq", "kind": "proof"}
  ]
}
```

Advantages:
- Streaming-friendly: process one declaration at a time
- Language-agnostic: standard JSON format
- Complete: contains all graph information
- Accessible: easy for external tools and Python analysis
-/

namespace ImportGraph.Unified.Export

/-- Convert edge kind to JSON string -/
private def edgeKindToString (et : EdgeType) : String :=
  match et with
  | .extends => "extends"
  | .field => "field"
  | .signatureType => "sig"
  | .proofCall => "proof"
  | .defCall => "def"
  | .docRef => "docref"

/-- Convert declaration type to JSON string -/
private def declTypeToString (dt : DeclarationType) : String :=
  dt.label

/-- Convert edges of a specific type to JSON objects -/
private def edgesToJson (edgeMap : NameMap (Array Name)) (kind : String) (name : Name) :
    Array Json :=
  match edgeMap.find? name with
  | none => #[]
  | some targets => targets.map fun target =>
      Json.mkObj [
        ("target", Json.str target.toString),
        ("kind", Json.str kind)
      ]

/-- Build JSON array of edges for a given node -/
private def buildEdgesJson (name : Name)
    (g : UnifiedGraph) (allowedEdgeTypes : Option (Std.HashSet String)) :
    Array Json :=
  let allow (label : String) : Bool :=
    match allowedEdgeTypes with
    | none => true
    | some s => s.contains label

  let edges : Array Json :=
    (if allow "extends" then edgesToJson g.extendsEdges "extends" name else #[]) ++
    (if allow "field" then edgesToJson g.fieldEdges "field" name else #[]) ++
    (if allow "sig" then edgesToJson g.signatureEdges "sig" name else #[]) ++
    (if allow "proof" then edgesToJson g.proofEdges "proof" name else #[]) ++
    (if allow "def" then edgesToJson g.defEdges "def" name else #[]) ++
    (if allow "docref" then edgesToJson g.docRefEdges "docref" name else #[])

  edges

/-- Write unified graph to NDJSON format (newline-delimited JSON) -/
public def writeUnifiedGraphToNdjson
    (g : UnifiedGraph)
    (filePath : System.FilePath)
    (allowedEdgeTypes : Option (Std.HashSet String) := none) : IO Unit := do
  IO.eprintln s!"[Unified NDJSON] Writing unified graph to {filePath}"

  let handle ← IO.FS.Handle.mk filePath IO.FS.Mode.write

  let mut nodeCount := 0
  let mut edgeCount := 0

  -- Write one JSON object per declaration
  for (name, declType) in g.nodeTypes.toList do
    let modName := (g.nodeModules.find? name |>.getD .anonymous).toString

    let edges := buildEdgesJson name g allowedEdgeTypes
    edgeCount := edgeCount + edges.size

    let nodeJson : Json := Json.mkObj [
      ("name", Json.str name.toString),
      ("decl_type", Json.str (declTypeToString declType)),
      ("module", Json.str modName),
      ("edges", Json.arr edges)
    ]

    handle.putStrLn (Json.compress nodeJson)
    nodeCount := nodeCount + 1

    if nodeCount % 10000 == 0 then
      IO.eprintln s!"[Unified NDJSON] Processed {nodeCount} nodes..."

  _ ← handle.flush

  -- Statistics
  IO.eprintln s!"[Unified NDJSON] Wrote {nodeCount} nodes and {edgeCount} edges"
  IO.eprintln s!"[Unified NDJSON] File: {filePath}"

end ImportGraph.Unified.Export
