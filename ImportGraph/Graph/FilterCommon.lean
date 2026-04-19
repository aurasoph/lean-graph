/-
Copyright (c) 2024 ImportGraph Contributors. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: ImportGraph Contributors
-/
module

public import Lean.Environment
public import Lean.CoreM
import Lean.Meta.Instances
import Lean.AuxRecursor
import Lean.ProjFns
import Lean.DeclarationRange
import Lean.Meta.Match.MatcherInfo
import Lean.Meta.Match.MatchEqsExt
import Lean.Structure

open Lean Meta

/-!
# Common Filtering Logic for Dependency Graphs

Shared filtering utilities used across all graph modes.

**Design goal**: a node in the graph corresponds to a declaration that has its own
entry in the Mathlib/Lean documentation (doc-gen4 visible API). A declaration is
included if and only if it would appear as a standalone entry in the docs:

- Has a source range (`isExplicitAPI`) — excludes compiler-generated declarations
  (match blocks, equation lemmas, auto-generated constructors)
- Is not an auxiliary recursor or noConfusion lemma
- Is not a projection function — field accessors like `Mul.mul` are shown as
  fields on the parent structure's page, not as standalone entries

Everything else — typeclass instances, tactic-layer declarations, opaque defs —
is included, matching exactly what doc-gen4 documents.

Pass `includeAll := true` to bypass all filtering (debug / exhaustive mode).
-/

namespace Lean.Environment

/--
Determine if a declaration represents part of the "Explicit API" (written by a human).
Identifies compiler-generated "ghost" declarations by checking source position.
-/
public def isExplicitAPI (env : Environment) (name : Name) : Bool :=
  match Lean.declRangeExt.find? env name with
  | none => false
  | some ranges =>
    match name.getPrefix with
    | .anonymous => true
    | prefixName =>
      match Lean.declRangeExt.find? env prefixName with
      | none => true
      | some parentRanges =>
        -- Piggyback check: auto-generated children share the parent's selection range.
        ranges.selectionRange.pos != parentRanges.selectionRange.pos

/--
Get the "parent" declaration for a compiler-generated declaration.
Used to surface the meaningful parent when expanding through filtered nodes.
-/
public def getParentDeclaration (env : Environment) (name : Name) : Name :=
  if let some info := env.find? name then
    match info with
    | .ctorInfo val => val.induct
    | .recInfo val => val.name.getPrefix
    | _ => name.getPrefix
  else
    name.getPrefix

/--
Whether a declaration should appear as a node in the dependency graph.
Matches doc-gen4's visible API: every node corresponds to a standalone
documentation entry.

Pass `includeAll := true` to skip all filtering (exhaustive/debug mode).
-/
public def shouldIncludeConstant (env : Environment) (name : Name)
    (includeAll : Bool := false) : Bool :=
  if includeAll then true
  else
    !name.isInternalDetail &&
    isExplicitAPI env name &&
    !isAuxRecursor env name &&
    !isNoConfusion env name &&
    !isProjectionFn env name

/-- Like `shouldIncludeConstant` but additionally excludes inductive types,
opaque defs, and quotient types from proof dependency graphs (they contribute
no proof-term content). -/
public def shouldIncludeConstantInProofDeps (env : Environment) (name : Name)
    (includeAll : Bool := false) : Bool :=
  shouldIncludeConstant env name includeAll &&
  match env.find? name with
  | some (.inductInfo _) | some (.opaqueInfo _) | some (.quotInfo _) => false
  | _ => true

/--
Apply filtering to a dependency list, expanding through excluded nodes to
recover their mathematical content.

When a dependency is excluded (e.g. a compiler-generated match block or
equation lemma), we DFS into its body to find the real declarations inside.
Projection functions are never expanded — their bodies are pure field accesses.

Set `isProof := true` when processing proof/definition bodies to use the
stricter `shouldIncludeConstantInProofDeps` gate.
-/
public def applyFiltering (env : Environment) (deps : Array Name)
    (includeAll : Bool := false) (isProof : Bool := false) : CoreM (Array Name) := do
  let shouldInclude (n : Name) : Bool :=
    if isProof then shouldIncludeConstantInProofDeps env n includeAll
    else shouldIncludeConstant env n includeAll

  let mut result : Array Name := #[]
  let mut resultSeen : NameSet := {}

  for startDep in deps do
    let mut stack : Array Name := #[startDep]
    let mut dfsSeen : NameSet := {}

    while !stack.isEmpty do
      let dep := stack.back!
      stack := stack.pop

      if dfsSeen.contains dep then continue
      dfsSeen := dfsSeen.insert dep

      if shouldInclude dep then
        if !resultSeen.contains dep then
          result := result.push dep
          resultSeen := resultSeen.insert dep
      else
        -- Redirect to meaningful parent (e.g. constructor → inductive)
        let parent := getParentDeclaration env dep
        if parent != dep && env.contains parent then
          if shouldInclude parent && !resultSeen.contains parent then
            result := result.push parent
            resultSeen := resultSeen.insert parent

        -- Expand through compiler-generated nodes to find real content.
        -- Do not expand through projection functions (body is just a field access).
        if isProof && !isProjectionFn env dep then
          if let some info := env.find? dep then
            let subDeps := match info with
              | .thmInfo val  => val.value.getUsedConstants
              | .defnInfo val => val.value.getUsedConstants
              | _ => #[]
            for subDep in subDeps do
              stack := stack.push subDep

  return result

public def applyTransitiveClosure (env : Environment) (deps : Array Name)
    (includeAll : Bool := false) : CoreM (Array Name) :=
  applyFiltering env deps includeAll false

public def applyTransitiveClosureForProofDeps (env : Environment) (deps : Array Name)
    (includeAll : Bool := false) : CoreM (Array Name) :=
  applyFiltering env deps includeAll true

end Lean.Environment
