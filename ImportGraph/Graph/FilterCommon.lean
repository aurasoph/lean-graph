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

**Design goal**: a dependency edge means "mathematical knowledge required to understand
or verify this declaration" — not "Lean kernel object referenced by this proof term."

Four filter categories:
1. **Compiler artifacts** — equation lemmas, match blocks, declarations without a distinct
   source position. Identified by `isExplicitAPI`.
2. **Structural plumbing** — auto-generated `A.toB` coercions from `extends`, explicitly
   named class hierarchy coercions, and all class projection functions (field accessors
   like `Mul.mul`, `Norm.norm`). Bodies are pure field accesses with no mathematical content.
3. **Typeclass instances** — filtered pragmatically to avoid noise from instance proof
   bodies leaking internal lemmas. Use `includeAll := true` to restore.
4. **Tactic internals** — omega/grind/ring/aesop infrastructure. Filtered principally:
   no mathematical content to surface underneath these names.

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
        ranges.selectionRange.pos != parentRanges.selectionRange.pos

private partial def isTransitiveStructureAncestor
    (env : Environment) (structName : Name) (targetName : Name)
    (visited : NameSet := {}) : Bool :=
  if visited.contains structName then false
  else
    match getStructureInfo? env structName with
    | none => false
    | some info =>
      let visited := visited.insert structName
      info.parentInfo.any fun p =>
        p.structName == targetName ||
        isTransitiveStructureAncestor env p.structName targetName visited

private def isClassDeclaration (env : Environment) (structName : Name) : Bool :=
  match getStructureInfo? env structName with
  | none => false
  | some info =>
    (info.parentInfo.any fun p =>
      (env.getProjectionFnInfo? p.projFn).any (·.fromClass))
    ||
    (info.fieldInfo.any fun f =>
      (env.getProjectionFnInfo? f.projFn).any (·.fromClass))

/-- Determine if a name is an auto-generated or manually-written structural parent accessor. -/
private def isStructureParentAccessor (env : Environment) (name : Name) : Bool :=
  match getStructureInfo? env name.getPrefix with
  | none => false
  | some sinfo =>
    if sinfo.parentInfo.any (fun p => p.projFn == name) then
      true
    else
      let lastComp := name.getString!
      if lastComp.startsWith "to" && lastComp.length > 2 then
        let stripped := lastComp.toRawSubstring.drop 2 |>.toString
        if stripped.startsWith "OfNat" && stripped.any Char.isDigit then
          (getStructureInfo? env name.getPrefix).isSome
        else if isClassDeclaration env name.getPrefix then
          true
        else
          let targetName := Name.str Name.anonymous stripped
          match getStructureInfo? env targetName with
          | none => false
          | some _ => isTransitiveStructureAncestor env name.getPrefix targetName
      else
        false

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

/-- Detect if a name follows the anonymous-instance naming convention (`inst*` or `.inst*`).
Used as a fast pre-filter; named instances are caught by `isInstanceCore`. -/
public def isLikelyInstance (name : Name) : Bool :=
  let s := name.toString
  s.startsWith "inst" || (s.splitOn ".inst").length > 1

/-- Determine if a constant belongs to tactic infrastructure. -/
public def isTacticInternal (name : Name) : Bool :=
  (`Lean.Grind).isPrefixOf name ||
  (`Lean.Omega).isPrefixOf name ||
  (`Lean.RArray).isPrefixOf name ||
  (`Lean.Meta).isPrefixOf name ||
  (`Lean.Elab).isPrefixOf name ||
  (`Lean.Core).isPrefixOf name ||
  (`Lean.Server).isPrefixOf name ||
  (`Lean.Lsp).isPrefixOf name ||
  (`Int.Linear).isPrefixOf name ||
  (`Nat.Linear).isPrefixOf name ||
  (`Nat.ToInt).isPrefixOf name ||
  (`Mathlib.Tactic).isPrefixOf name ||
  (`Mathlib.TacticAnalysis).isPrefixOf name ||
  (`Mathlib.Meta).isPrefixOf name ||
  (`Std.Internal).isPrefixOf name ||
  (`Std.Tactic).isPrefixOf name ||
  (`Std.Sat).isPrefixOf name ||
  (`Aesop).isPrefixOf name ||
  (`Qq).isPrefixOf name

/--
Whether a declaration should appear as a node in the dependency graph.

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
    !(env.find? name matches some (.recInfo _)) &&
    !(Lean.Meta.getMatcherInfoCore? env name |>.isSome) &&
    !isStructureParentAccessor env name &&
    !isProjectionFn env name &&
    !isLikelyInstance name &&
    !isTacticInternal name

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

When a dependency is excluded (e.g. a compiler-generated match block), we DFS
into its body to find the real declarations inside.

Expansion is gated: we do NOT expand through projection functions, structural
parent accessors, typeclass instances, or tactic internals — these contain no
mathematical content worth surfacing.
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
        let parent := getParentDeclaration env dep
        if parent != dep && env.contains parent then
          if shouldInclude parent && !resultSeen.contains parent then
            result := result.push parent
            resultSeen := resultSeen.insert parent

        if isProof &&
           !isProjectionFn env dep &&
           !isStructureParentAccessor env dep &&
           !isLikelyInstance dep &&
           !isTacticInternal dep then
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
