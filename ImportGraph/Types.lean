/-
Copyright (c) 2024 ImportGraph Contributors. All rights reserved.
Modifications (c) 2026 Evan Wang. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: ImportGraph Contributors
-/
module

public import Lean.Data.NameMap.Basic

open Lean

/-!
# Core Type Definitions

Centralized definitions for the unified dependency graph system.

## Declaration Types

Semantic classification of Lean declarations, extended to match jixia's 8 symbol types:
- Definitions: definition, opaque, axiom
- Types: structure, class, inductive, constructor
- Logic: theorem
- Special: quotient (quotient type), recursor (inductive recursor)
- Instance: instance
- Other: other

## Edge Types

Categorization of dependency relationships in the unified graph:
- **extends**: Structure/class inheritance
- **field**: Field/parameter composition
- **signatureType**: Type appearing in signature
- **proofCall**: Theorem/definition invocation in proof
- **defCall**: Definition invocation in definition body
- **docRef**: Backtick reference in docstring
-/

namespace ImportGraph.Types

/-- Edge type categorization for unified graph dependencies -/
public inductive EdgeType where
  | extends : EdgeType
  | field : EdgeType
  | signatureType : EdgeType
  | proofCall : EdgeType
  | defCall : EdgeType
  | docRef : EdgeType
  deriving Inhabited, BEq, Hashable, Repr

def EdgeType.color : EdgeType → String
  | .extends => "blue"
  | .field => "cyan"
  | .signatureType => "orange"
  | .proofCall => "green"
  | .defCall => "lime"
  | .docRef => "purple"

def EdgeType.style : EdgeType → String
  | .extends => "solid"
  | .field => "solid"
  | .signatureType => "dashed"
  | .proofCall => "solid"
  | .defCall => "solid"
  | .docRef => "dotted"

def EdgeType.penwidth : EdgeType → Nat
  | .extends => 3
  | .field => 2
  | .signatureType => 1
  | .proofCall => 3
  | .defCall => 2
  | .docRef => 1

def EdgeType.label : EdgeType → String
  | .extends => "extends"
  | .field => "field"
  | .signatureType => "sig"
  | .proofCall => "proof"
  | .defCall => "def"
  | .docRef => "docref"

/-- Declaration type classification for nodes, extended with quotient and recursor -/
public inductive DeclarationType where
  | structure : DeclarationType
  | class : DeclarationType
  | instance : DeclarationType
  | theorem : DeclarationType
  | definition : DeclarationType
  | opaque : DeclarationType
  | inductive : DeclarationType
  | constructor : DeclarationType
  | quotient : DeclarationType
  | recursor : DeclarationType
  | axiom : DeclarationType
  | other : DeclarationType
  deriving Inhabited, BEq, Repr

public def DeclarationType.shape : DeclarationType → String
  | .structure | .class => "ellipse"
  | .instance | .definition | .opaque | .axiom => "box"
  | .theorem => "diamond"
  | .inductive | .constructor => "triangle"
  | .quotient => "box"
  | .recursor => "triangle"
  | .other => "ellipse"

public def DeclarationType.fillColor : DeclarationType → String
  | .structure => "#b3d9ff"
  | .class => "#99ccff"
  | .instance => "#ffd9b3"
  | .theorem => "#c1f0c1"
  | .definition => "#e2f9e2"
  | .opaque => "#d9d9e8"
  | .inductive => "#d7b3ff"
  | .constructor => "#edd9ff"
  | .quotient => "#dcdced"
  | .recursor => "#e8ccff"
  | .axiom => "#ffb3b3"
  | .other => "#e0e0e0"

public def DeclarationType.label : DeclarationType → String
  | .structure => "struct"
  | .class => "class"
  | .instance => "inst"
  | .theorem => "thm"
  | .definition => "def"
  | .opaque => "opaque"
  | .inductive => "ind"
  | .constructor => "ctor"
  | .quotient => "quot"
  | .recursor => "rec"
  | .axiom => "axiom"
  | .other => "other"

/-- Unified graph structure combining all dependency types -/
public structure UnifiedGraph where
  nodes : NameSet
  nodeTypes : NameMap DeclarationType
  nodeModules : NameMap Name  -- name → defining Lean module
  extendsEdges : NameMap (Array Name)
  fieldEdges : NameMap (Array Name)
  signatureEdges : NameMap (Array Name)
  proofEdges : NameMap (Array Name)
  defEdges : NameMap (Array Name)
  docRefEdges : NameMap (Array Name)
  deriving Inhabited

end ImportGraph.Types
