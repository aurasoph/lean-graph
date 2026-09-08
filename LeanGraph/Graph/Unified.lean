/-
Copyright (c) 2024 LeanGraph Contributors. All rights reserved.
Modifications (c) 2026 Evan Wang. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: LeanGraph Contributors
-/
module

public import Lean.Environment
public import Lean.CoreM
public import LeanGraph.Types
import Lean.Data.NameMap.Basic
import Lean.Structure
import Lean.Class
import Lean.DocString
import Lean.Meta.Instances
import LeanGraph.Graph.Structures
import LeanGraph.Graph.TypeDeps
import LeanGraph.Graph.ProofDeps
import LeanGraph.Graph.TransitiveClosure
public import LeanGraph.Graph.FilterCommon

open Lean
open LeanGraph.Types

/-!
# Unified Dependency Graph

The primary object is `rawUnifiedGraph`: the faithful, unfiltered kernel
dependency graph. Its nodes are every constant in scope and its edges are exactly
`getUsedConstants` over each constant's type (signature edges) and value
(proof/def edges) — no filtering, no expand-through, matching the dependency
discipline of `lean4export`.

`unifiedGraph` is a derived *readable* view: it applies the inclusion filter and
edge expand-through as a post-pass over the raw graph, and layers on the
semantic overlays that are not kernel dependencies — structure inheritance /
fields and docstring backtick references.

Edge Types:
1. **extends**: Structure inheritance (overlay)
2. **field**: Field/parameter reference (overlay)
3. **signatureType**: Type appearing in signature
4. **proofCall**: Theorem/lemma invocation
5. **defCall**: Definition invocation
6. **docRef**: Backtick reference in docstring (`` `Name ``) (overlay)
-/

namespace LeanGraph.Unified

/-- Classify a constant's declaration type -/
def classifyDeclarationType (env : Environment) (name : Name) : DeclarationType :=
  match env.find? name with
  | none => .other
  | some info =>
    if Lean.isClass env name then .class
    else if let some _ := Lean.getStructureInfo? env name then .structure
    else if Lean.isStructure env name then .structure
    else if Lean.Meta.isInstanceCore env name then .instance
    else match info with
      | .thmInfo _               => .theorem
      | .defnInfo _              => .definition
      | .quotInfo _              => .quotient
      | .opaqueInfo _            => .opaque
      | .axiomInfo _             => .axiom
      | .inductInfo _            => .inductive
      | .ctorInfo _              => .constructor
      | .recInfo _               => .recursor

def nodesFromMap (graph : NameMap (Array Name)) : NameSet :=
  graph.foldl (fun acc name deps =>
    let acc := acc.insert name
    deps.foldl (fun acc dep => acc.insert dep) acc
  ) ∅

def nodesFromSigMap (graph : NameMap (Array (Name × SigEdgeMeta))) : NameSet :=
  graph.foldl (fun acc name deps =>
    let acc := acc.insert name
    deps.foldl (fun acc (dep, _) => acc.insert dep) acc
  ) ∅

/-- The module that defines `name`, when it comes from an imported module. -/
private def moduleOf (env : Environment) (name : Name) : Name :=
  match env.getModuleIdxFor? name with
  | some idx => env.header.moduleNames[idx.toNat]!
  | none => .anonymous

/-!
## Docstring backtick reference extraction

Parses docstrings for `` `Name `` patterns where `Name` is a valid Lean identifier
(letters, digits, `.`, `_`, `'`). Double-backtick code spans (`` ``code`` ``) are
skipped. References are validated against the environment and filtered to
declarations that pass the standard inclusion check.
-/

private def isDocNameChar (c : Char) : Bool :=
  c.isAlphanum || c == '.' || c == '_' || c == '\''

private def skipCodeSpan : List Char → List Char
  | '`' :: '`' :: rest => rest
  | [] => []
  | _ :: rest => skipCodeSpan rest

private def collectName : List Char → String → String × List Char
  | [], s => (s, [])
  | c :: rest, s =>
    if isDocNameChar c then collectName rest (s.push c) else (s, c :: rest)

/-- Extract all `` `Name `` backtick references from a docstring. -/
private def extractDocRefNames (docstring : String) : Array String :=
  let rec go : List Char → Array String → Array String
    | [], acc => acc
    | '`' :: '`' :: rest, acc => go (skipCodeSpan rest) acc
    | '`' :: c :: rest, acc =>
      if c.isAlpha || c == '_' then
        let (name, rest') := collectName (c :: rest) ""
        go rest' (if name.isEmpty then acc else acc.push name)
      else
        go (c :: rest) acc
    | _ :: rest, acc => go rest acc
  partial_fixpoint
  go docstring.toList #[]

private def stringToName (s : String) : Name :=
  if s.isEmpty then .anonymous
  else s.splitOn "." |>.foldl (fun acc part => .str acc part) .anonymous

/--
Build docref edges: extract all `` `Name `` backtick references from docstrings
that resolve to known, included declarations.
-/
private def buildDocRefEdges (env : Environment) (included : NameSet) :
    CoreM (NameMap (Array Name)) := do
  let mut docRefEdges : NameMap (Array Name) := {}
  for (name, _) in env.constants.toList do
    if !included.contains name then continue
    if let some docStr ← Lean.findDocString? env name then
      let refStrs := extractDocRefNames docStr
      let mut validRefs : Array Name := #[]
      for refStr in refStrs do
        let refName := stringToName refStr
        if refName != .anonymous && included.contains refName &&
           refName != name && !validRefs.contains refName then
          validRefs := validRefs.push refName
      if !validRefs.isEmpty then
        docRefEdges := docRefEdges.insert name validRefs
  return docRefEdges

/--
Build the raw, unfiltered kernel dependency graph — the primary graph object.

Nodes are every constant in scope. Signature edges are `getUsedConstants` over
each constant's type (with per-edge metadata); proof edges (for theorems) and def
edges (for everything else with a value) are `getUsedConstants` over its value.
No filtering, no expand-through, no parent-redirect. Structure/field/docref
overlays are left empty — they are not kernel dependencies (see `unifiedGraph`).
-/
public def rawUnifiedGraph (env : Environment) : CoreM UnifiedGraph := do
  IO.eprintln "[Raw] Building raw kernel dependency graph..."
  let mut nodes         : NameSet := {}
  let mut nodeTypes     : NameMap DeclarationType := {}
  let mut nodeModules   : NameMap Name := {}
  let mut nodeDocstrings: NameMap String := {}
  let mut nodeInstances : NameSet := {}
  let mut signatureEdges: NameMap (Array (Name × SigEdgeMeta)) := {}
  let mut proofEdges    : NameMap (Array Name) := {}
  let mut defEdges      : NameMap (Array Name) := {}
  let mut processed := 0

  for (name, info) in env.constants.toList do
    processed := processed + 1
    if processed % 20000 == 0 then
      IO.eprintln s!"[Raw] Processing constant {processed}: {name}"

    nodes := nodes.insert name
    let dt := classifyDeclarationType env name
    nodeTypes := nodeTypes.insert name dt
    nodeModules := nodeModules.insert name (moduleOf env name)
    if let some doc ← Lean.findDocString? env name then
      if !doc.isEmpty then nodeDocstrings := nodeDocstrings.insert name doc
    if Lean.Meta.isInstanceCore env name then
      nodeInstances := nodeInstances.insert name

    let sig := Lean.Environment.rawSigEdges info
    if !sig.isEmpty then signatureEdges := signatureEdges.insert name sig

    let vals := Lean.Environment.valueDeps env name info
    if !vals.isEmpty then
      if dt == .theorem then proofEdges := proofEdges.insert name vals
      else defEdges := defEdges.insert name vals

  return {
    nodes, nodeTypes, nodeModules, nodeDocstrings, nodeInstances,
    signatureEdges, proofEdges, defEdges,
    extendsEdges := {}, fieldEdges := {}, docRefEdges := {}
  }

/--
Derive the readable (filtered) view from the raw graph.

The inclusion filter is applied as a post-pass: signature edges are filtered and
parent-redirected, proof/def edges are run through the expand-through closure, and
the structure/field/docref overlays are attached. Node metadata is read back from
the raw graph.
-/
public def UnifiedGraph.readableView (env : Environment) (raw : UnifiedGraph)
    (includeAll : Bool := false) : CoreM UnifiedGraph := do
  -- Inclusion sets: the filter predicate, computed once.
  let mut included      : NameSet := {}
  let mut proofIncluded : NameSet := {}
  for (name, _) in env.constants.toList do
    if Lean.Environment.shouldIncludeConstant env name includeAll then
      included := included.insert name
    if Lean.Environment.shouldIncludeConstantInProofDeps env name includeAll then
      proofIncluded := proofIncluded.insert name

  -- Kernel edges: filter the raw signature and value edges.
  IO.eprintln "[Unified] Filtering signature edges..."
  let mut signatureEdges : NameMap (Array (Name × SigEdgeMeta)) := {}
  for name in included.toList do
    let rawSig := raw.signatureEdges.find? name |>.getD #[]
    signatureEdges := signatureEdges.insert name
      (Lean.Environment.filterSigEdges env rawSig includeAll)

  IO.eprintln "[Unified] Filtering proof and definition edges..."
  let mut proofEdges : NameMap (Array Name) := {}
  let mut defEdges   : NameMap (Array Name) := {}
  for (name, info) in env.constants.toList do
    if !proofIncluded.contains name then continue
    match info with
    | .thmInfo _ | .defnInfo _ | .axiomInfo _ =>
      let dt := raw.nodeTypes.find? name |>.getD .other
      let rawVals := (if dt == .theorem then raw.proofEdges.find? name
                      else raw.defEdges.find? name).getD #[]
      let processed ← Lean.Environment.applyTransitiveClosureForProofDeps env rawVals includeAll
      if dt == .theorem then proofEdges := proofEdges.insert name processed
      else defEdges := defEdges.insert name processed
    | _ => pure ()

  -- Overlays that are not part of the raw kernel graph.
  IO.eprintln "[Unified] Analyzing structures..."
  let structures ← env.analyzeStructures includeAll
  IO.eprintln "[Unified] Extracting docstring references..."
  let docRefEdges ← buildDocRefEdges env included

  -- Merge node sets and read metadata back from the raw graph.
  IO.eprintln "[Unified] Merging nodes..."
  let mut allNodes := nodesFromMap structures.extendsEdges
  allNodes := (nodesFromMap structures.fieldEdges).foldl (·.insert ·) allNodes
  allNodes := (nodesFromSigMap signatureEdges).foldl (·.insert ·) allNodes
  allNodes := (nodesFromMap proofEdges).foldl (·.insert ·) allNodes
  allNodes := (nodesFromMap defEdges).foldl (·.insert ·) allNodes
  allNodes := (nodesFromMap docRefEdges).foldl (·.insert ·) allNodes

  let nodeTypes : NameMap DeclarationType := allNodes.foldl (fun acc name =>
    acc.insert name (raw.nodeTypes.find? name |>.getD .other)) {}
  let nodeModules : NameMap Name := allNodes.foldl (fun acc name =>
    acc.insert name (raw.nodeModules.find? name |>.getD .anonymous)) {}
  let mut nodeDocstrings : NameMap String := {}
  let mut nodeInstances : NameSet := {}
  for name in allNodes.toList do
    if let some doc := raw.nodeDocstrings.find? name then
      nodeDocstrings := nodeDocstrings.insert name doc
    if raw.nodeInstances.contains name then
      nodeInstances := nodeInstances.insert name

  return {
    nodes := allNodes, nodeTypes, nodeModules, nodeDocstrings, nodeInstances,
    extendsEdges := structures.extendsEdges, fieldEdges := structures.fieldEdges,
    signatureEdges, proofEdges, defEdges, docRefEdges
  }

/--
The readable (filtered) unified dependency graph: `rawUnifiedGraph` followed by
the inclusion-filter post-pass and semantic overlays. Pass `includeAll := true`
to bypass filtering.
-/
public def unifiedGraph (env : Environment) (includeAll : Bool := false) : CoreM UnifiedGraph := do
  let raw ← rawUnifiedGraph env
  UnifiedGraph.readableView env raw includeAll

public def UnifiedGraph.totalEdgeCount (g : UnifiedGraph) : Nat :=
  let count (m : NameMap (Array Name)) := m.foldl (fun acc _ deps => acc + deps.size) 0
  let countSig (m : NameMap (Array (Name × SigEdgeMeta))) := m.foldl (fun acc _ deps => acc + deps.size) 0
  count g.extendsEdges + count g.fieldEdges + countSig g.signatureEdges +
  count g.proofEdges + count g.defEdges + count g.docRefEdges

public def UnifiedGraph.edgeCountByType (g : UnifiedGraph) (et : EdgeType) : Nat :=
  let count (m : NameMap (Array Name)) := m.foldl (fun acc _ deps => acc + deps.size) 0
  let countSig (m : NameMap (Array (Name × SigEdgeMeta))) := m.foldl (fun acc _ deps => acc + deps.size) 0
  match et with
  | .extends => count g.extendsEdges
  | .field => count g.fieldEdges
  | .signatureType => countSig g.signatureEdges
  | .proofCall => count g.proofEdges
  | .defCall => count g.defEdges
  | .docRef => count g.docRefEdges

end LeanGraph.Unified
