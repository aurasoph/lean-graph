/-
Copyright (c) 2024 ImportGraph Contributors. All rights reserved.
Modifications (c) 2026 Evan Wang. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: ImportGraph Contributors
-/
module

public import Lean.Environment
public import Lean.CoreM
public import ImportGraph.Types
import Lean.Data.NameMap.Basic
import Lean.Structure
import Lean.Class
import Lean.DocString
import Lean.Meta.Instances
import ImportGraph.Graph.Structures
import ImportGraph.Graph.TypeDeps
import ImportGraph.Graph.ProofDeps
import ImportGraph.Graph.TransitiveClosure
public import ImportGraph.Graph.FilterCommon

open Lean
open ImportGraph.Types

/-!
# Unified Dependency Graph

Combines:
- Structure inheritance and fields
- Type signature dependencies
- Proof and definition implementation dependencies
- Docstring backtick references

Edge Types:
1. **extends**: Structure inheritance
2. **field**: Field/parameter reference
3. **signatureType**: Type appearing in signature
4. **proofCall**: Theorem/lemma invocation
5. **defCall**: Definition invocation
6. **docRef**: Backtick reference in docstring (`` `Name ``)
-/

namespace ImportGraph.Unified

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

/-- Pre-computed symbol context for efficient phase separation -/
private structure SymbolContext where
  includedSymbols  : NameSet
  proofDepsSymbols : NameSet
  declTypes        : NameMap DeclarationType
  declModules      : NameMap Name

/-- Single-pass symbol discovery: classify all symbols and compute module mappings -/
private def discoverSymbols (env : Environment) (includeAll : Bool) : SymbolContext :=
  let (includedSymbols, proofDepsSymbols, declTypes, declModules) :=
    env.constants.toList.foldl (fun (incl, proof, types, mods) (name, _) =>
      let incl' :=
        if Lean.Environment.shouldIncludeConstant env name includeAll then
          incl.insert name
        else
          incl
      let types' :=
        if incl'.contains name then
          types.insert name (classifyDeclarationType env name)
        else
          types
      let modName : Name := match env.getModuleIdxFor? name with
        | some idx => env.header.moduleNames[idx.toNat]!
        | none => .anonymous
      let mods' :=
        if incl'.contains name then
          mods.insert name modName
        else
          mods
      let proof' :=
        if Lean.Environment.shouldIncludeConstantInProofDeps env name includeAll then
          proof.insert name
        else
          proof
      (incl', proof', types', mods')
    ) (∅, ∅, {}, {})
  {
    includedSymbols
    proofDepsSymbols
    declTypes
    declModules
  }

/-- Build proof and definition edges with inline categorization using pre-computed context -/
private def buildProofAndDefEdges (env : Environment) (ctx : SymbolContext) (includeAll : Bool) :
    CoreM (NameMap (Array Name) × NameMap (Array Name)) := do
  let mut proofEdges : NameMap (Array Name) := {}
  let mut defEdges : NameMap (Array Name) := {}
  let mut processedCount := 0

  IO.eprintln "[Unified] Analyzing proof and definition implementations..."

  for (name, info) in env.constants.toList do
    processedCount := processedCount + 1

    if processedCount % 5000 == 0 then
      IO.eprintln s!"[Unified] Processing constant {processedCount}: {name}"

    if ctx.proofDepsSymbols.contains name then
      let shouldProcess : Bool := match info with
        | .thmInfo _ | .defnInfo _ | .axiomInfo _ => true
        | _ => false

      if shouldProcess then
        let deps : Array Name := match info with
          | .thmInfo val => val.value.getUsedConstants
          | .defnInfo val =>
            let direct := val.value.getUsedConstants
            let irredDeps : Array Name :=
              match name with
              | .str pre s =>
                match env.find? (.str pre (s ++ "_def")) with
                | some (.thmInfo defLemma) => defLemma.type.getUsedConstants
                | _ => #[]
              | _ => #[]
            (direct ++ irredDeps).toList.eraseDups.toArray
          | .axiomInfo _ => #[]
          | _ => #[]

        let processedDeps ← Lean.Environment.applyTransitiveClosureForProofDeps env deps includeAll

        -- Route to proofEdges or defEdges based on source node type
        let sourceType := ctx.declTypes.find? name |>.getD .other
        if sourceType == .theorem then
          proofEdges := proofEdges.insert name processedDeps
        else
          defEdges := defEdges.insert name processedDeps

  return (proofEdges, defEdges)

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
Build docref edges using pre-computed context: extract all `` `Name `` backtick
references from docstrings that resolve to known, included declarations.
-/
private def buildDocRefEdgesWithCtx (env : Environment) (ctx : SymbolContext) :
    CoreM (NameMap (Array Name)) := do
  let mut docRefEdges : NameMap (Array Name) := {}
  for (name, _) in env.constants.toList do
    if !ctx.includedSymbols.contains name then continue
    if let some docStr ← Lean.findDocString? env name then
      let refStrs := extractDocRefNames docStr
      let mut validRefs : Array Name := #[]
      for refStr in refStrs do
        let refName := stringToName refStr
        if refName != .anonymous && ctx.includedSymbols.contains refName &&
           refName != name && !validRefs.contains refName then
          validRefs := validRefs.push refName
      if !validRefs.isEmpty then
        docRefEdges := docRefEdges.insert name validRefs
  return docRefEdges

/--
Build the unified dependency graph with explicit phase separation.

Phase 1: Symbol discovery (single pass)
Phase 2: Edge computation (parallel builds)
Phase 3: Node merging
Phase 4: Type/module lookup from pre-computed context
-/
public def unifiedGraph (env : Environment) (includeAll : Bool := false) : CoreM UnifiedGraph := do

  -- Phase 1: Discover all included symbols, classify types, map modules
  IO.eprintln "[Unified] Discovering symbols..."
  let ctx := discoverSymbols env includeAll

  -- Phase 2: Build all edge types
  IO.eprintln "[Unified] Analyzing structures..."
  let structures ← env.analyzeStructures includeAll

  IO.eprintln "[Unified] Analyzing type signatures..."
  let typeDepsGraph ← env.typeDepsGraph includeAll

  IO.eprintln "[Unified] Analyzing proof and definition implementations..."
  let (proofEdges, defEdges) ← buildProofAndDefEdges env ctx includeAll

  IO.eprintln "[Unified] Extracting docstring references..."
  let docRefEdges ← buildDocRefEdgesWithCtx env ctx

  -- Phase 3: Merge all node sets
  IO.eprintln "[Unified] Merging nodes..."
  let mut allNodes := nodesFromMap structures.extendsEdges
  allNodes := (nodesFromMap structures.fieldEdges).foldl (·.insert ·) allNodes
  allNodes := (nodesFromSigMap typeDepsGraph).foldl (·.insert ·) allNodes
  allNodes := (nodesFromMap proofEdges).foldl (·.insert ·) allNodes
  allNodes := (nodesFromMap defEdges).foldl (·.insert ·) allNodes
  allNodes := (nodesFromMap docRefEdges).foldl (·.insert ·) allNodes

  -- Phase 4: Lookup node types and modules from pre-computed context
  IO.eprintln s!"[Unified] Populating node metadata..."
  let nodeTypes : NameMap DeclarationType := allNodes.foldl (fun acc name =>
    match ctx.declTypes.find? name with
    | some ty => acc.insert name ty
    | none => acc.insert name .other
  ) {}

  let nodeModules : NameMap Name := allNodes.foldl (fun acc name =>
    match ctx.declModules.find? name with
    | some mod => acc.insert name mod
    | none => acc.insert name .anonymous
  ) {}

  -- Phase 5: Collect docstrings and instance flags for included nodes
  IO.eprintln "[Unified] Collecting docstrings..."
  let mut nodeDocstrings : NameMap String := {}
  let mut nodeInstances : NameSet := {}
  for name in allNodes.toList do
    if let some doc ← Lean.findDocString? env name then
      if !doc.isEmpty then
        nodeDocstrings := nodeDocstrings.insert name doc
    if Lean.Meta.isInstanceCore env name then
      nodeInstances := nodeInstances.insert name

  return {
    nodes := allNodes
    nodeTypes := nodeTypes
    nodeModules := nodeModules
    nodeDocstrings := nodeDocstrings
    nodeInstances := nodeInstances
    extendsEdges := structures.extendsEdges
    fieldEdges := structures.fieldEdges
    signatureEdges := typeDepsGraph
    proofEdges := proofEdges
    defEdges := defEdges
    docRefEdges := docRefEdges
  }

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

end ImportGraph.Unified
