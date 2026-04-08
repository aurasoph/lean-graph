/-
Copyright (c) 2024 ImportGraph Contributors. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: ImportGraph Contributors
-/
module

public import Lean.Environment
public import Lean.CoreM
import Lean.Data.NameMap.Basic
import Lean.Structure
import ImportGraph.Graph.Structures
import ImportGraph.Graph.TypeDeps
import ImportGraph.Graph.ProofDeps
import ImportGraph.Graph.TransitiveClosure
public import ImportGraph.Graph.FilterCommon

open Lean

/-!
# Unified Dependency Graph

Combines:
- Structure inheritance and fields
- Type signature dependencies
- Proof and definition implementation dependencies

Edge Types:
1. **extends**: Structure inheritance
2. **field**: Field/parameter reference
3. **signatureType**: Type appearing in signature
4. **proofCall**: Theorem/lemma invocation
5. **defCall**: Definition invocation
-/

namespace ImportGraph.Unified

/-- Edge type categorization -/
public inductive EdgeType where
  | extends : EdgeType
  | field : EdgeType
  | signatureType : EdgeType
  | proofCall : EdgeType
  | defCall : EdgeType
  deriving Inhabited, BEq, Hashable, Repr

def EdgeType.color : EdgeType → String
  | .extends => "blue"
  | .field => "cyan"
  | .signatureType => "orange"
  | .proofCall => "green"
  | .defCall => "lime"

def EdgeType.style : EdgeType → String
  | .extends => "solid"
  | .field => "solid"
  | .signatureType => "dashed"
  | .proofCall => "solid"
  | .defCall => "solid"

def EdgeType.penwidth : EdgeType → Nat
  | .extends => 3
  | .field => 2
  | .signatureType => 1
  | .proofCall => 3
  | .defCall => 2

def EdgeType.label : EdgeType → String
  | .extends => "extends"
  | .field => "field"
  | .signatureType => "sig"
  | .proofCall => "proof"
  | .defCall => "def"

/-- Declaration type classification for nodes -/
public inductive DeclarationType where
  | structure : DeclarationType
  | class : DeclarationType
  | theorem : DeclarationType
  | definition : DeclarationType
  | inductive : DeclarationType
  | axiom : DeclarationType
  | other : DeclarationType
  deriving Inhabited, BEq, Repr

public def DeclarationType.shape : DeclarationType → String
  | .structure | .class => "ellipse"
  | .theorem => "diamond"
  | .definition => "box"
  | .inductive => "triangle"
  | .axiom => "box"
  | .other => "ellipse"

public def DeclarationType.fillColor : DeclarationType → String
  | .structure => "#b3d9ff"
  | .class => "#99ccff"
  | .theorem => "#c1f0c1"
  | .definition => "#e2f9e2"
  | .inductive => "#d7b3ff"
  | .axiom => "#ffb3b3"
  | .other => "#e0e0e0"

def DeclarationType.label : DeclarationType → String
  | .structure => "struct"
  | .class => "class"
  | .theorem => "thm"
  | .definition => "def"
  | .inductive => "ind"
  | .axiom => "axiom"
  | .other => "other"

/-- Unified graph structure -/
public structure UnifiedGraph where
  nodes : NameSet
  nodeTypes : NameMap DeclarationType
  extendsEdges : NameMap (Array Name)
  fieldEdges : NameMap (Array Name)
  signatureEdges : NameMap (Array Name)
  proofEdges : NameMap (Array Name)
  defEdges : NameMap (Array Name)
  deriving Inhabited

/-- Classify a constant's declaration type -/
def classifyDeclarationType (env : Environment) (name : Name) : DeclarationType :=
  match env.find? name with
  | none => .other
  | some info =>
    if let some _ := Lean.getStructureInfo? env name then
      .structure
    else if Lean.isStructure env name then .structure
    else match info with
      | .thmInfo _ => .theorem
      | .defnInfo _ => .definition
      | .axiomInfo _ => .axiom
      | .inductInfo _ => .inductive
      | _ => .other

def nodesFromMap (graph : NameMap (Array Name)) : NameSet :=
  graph.foldl (fun acc name deps =>
    let acc := acc.insert name
    deps.foldl (fun acc dep => acc.insert dep) acc
  ) ∅

/-- 
Build the unified dependency graph.
-/
public def unifiedGraph (env : Environment) 
    (tier : Environment.FilterTier := .standard)
    (includeInstances : Bool := false) : CoreM UnifiedGraph := do
  
  -- Step 1: Collect structures graph
  IO.eprintln "[Unified] Analyzing structures..."
  let structures ← env.analyzeStructures tier
  
  -- Step 2: Collect type signature graph
  IO.eprintln "[Unified] Analyzing type signatures..."
  let mut typeDepsGraph ← env.typeDepsGraph tier includeInstances
  
  -- Step 3: Collect proof dependencies graph
  IO.eprintln "[Unified] Analyzing proof implementations..."
  let proofDepsGraph ← env.proofDepsGraph tier includeInstances
  
  -- Step 4: Extract and merge node sets
  IO.eprintln "[Unified] Merging nodes..."
  let mut allNodes := nodesFromMap structures.extendsEdges
  allNodes := (nodesFromMap structures.fieldEdges).foldl (·.insert ·) allNodes
  allNodes := (nodesFromMap typeDepsGraph).foldl (·.insert ·) allNodes
  allNodes := (nodesFromMap proofDepsGraph).foldl (·.insert ·) allNodes
  
  -- Step 5: Classify nodes
  IO.eprintln s!"[Unified] Classifying {allNodes.size} nodes..."
  let mut nodeTypes : NameMap DeclarationType := {}
  for name in allNodes.toList do
    nodeTypes := nodeTypes.insert name (classifyDeclarationType env name)
  
  -- Step 6: Categorize edges
  IO.eprintln "[Unified] Categorizing edges..."
  let mut proofEdges : NameMap (Array Name) := {}
  let mut defEdges : NameMap (Array Name) := {}
  
  for (source, targets) in proofDepsGraph.toList do
    let sourceType := nodeTypes.find? source |>.getD .other
    if sourceType == .theorem then
      proofEdges := proofEdges.insert source targets
    else
      defEdges := defEdges.insert source targets
  
  return {
    nodes := allNodes
    nodeTypes := nodeTypes
    extendsEdges := structures.extendsEdges
    fieldEdges := structures.fieldEdges
    signatureEdges := typeDepsGraph
    proofEdges := proofEdges
    defEdges := defEdges
  }

public def UnifiedGraph.totalEdgeCount (g : UnifiedGraph) : Nat :=
  let count (m : NameMap (Array Name)) := m.foldl (fun acc _ deps => acc + deps.size) 0
  count g.extendsEdges + count g.fieldEdges + count g.signatureEdges + count g.proofEdges + count g.defEdges

/-- Get edge count for a specific edge type -/
public def UnifiedGraph.edgeCountByType (g : UnifiedGraph) (et : EdgeType) : Nat :=
  let count (m : NameMap (Array Name)) := m.foldl (fun acc _ deps => acc + deps.size) 0
  match et with
  | .extends => count g.extendsEdges
  | .field => count g.fieldEdges
  | .signatureType => count g.signatureEdges
  | .proofCall => count g.proofEdges
  | .defCall => count g.defEdges

end ImportGraph.Unified
