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

Shared filtering utilities used by TypeDeps and ProofDeps graphs.

**Design goal**: a dependency edge should mean "mathematical knowledge required to
understand or verify this theorem" — not "Lean kernel object referenced by this proof term."
See `docs/FILTERING.md` for the full design philosophy.

Four filter categories (see `docs/FILTERING.md` for details):
1. **Compiler artifacts** — equation lemmas, match blocks, constructors without unique
   source positions. Filtered by `isMechanicalDeclaration` via `isExplicitAPI`.
2. **Structural plumbing** — auto-generated `A.toB` coercions from `extends`, explicitly
   named class hierarchy coercions (`A.toB` where A is a typeclass), and all class projections
   (field accessors like `Mul.mul`, `Norm.norm`, `CategoryStruct.comp`). Projections are
   notation-elaboration artifacts whose bodies are pure field accesses with no mathematical
   content; the parent redirect to the class/structure (an `inductInfo`) is also excluded from
   proof deps. All projections filtered uniformly — no exceptions.
3. **Typeclass instances** — filtered *pragmatically* to avoid noise from instance proof
   bodies leaking internal lemmas. Use `--include-instances` to restore.
4. **Tactic internals** — omega/grind/ring/aesop infrastructure. Filtered *principally*:
   there is no mathematical content to surface underneath these names.

Filtering tiers:
- **Exhaustive**: Includes everything possible
- **Standard**: Applies all four categories above (default).
-/

namespace Lean.Environment

/-- Filtering tiers for dependency graphs -/
public inductive FilterTier where
  | exhaustive   -- Include everything possible
  | standard     -- Filter auxiliary/generated/mechanical (default)
  deriving Inhabited, BEq

/-- 
Determine if a declaration represents part of the "Explicit API" (written by a human).
This function rigorously identifies compiler-generated "ghost" declarations.
-/
public def isExplicitAPI (env : Environment) (name : Name) : Bool :=
  match Lean.declRangeExt.find? env name with
  | none => false -- No range at all: definitely compiler-generated (matchers, eq lemmas, etc.)
  | some ranges =>
    match name.getPrefix with
    | .anonymous => true -- Top-level: definitely written in source
    | prefixName =>
      match Lean.declRangeExt.find? env prefixName with
      | none => true -- Parent has no range: this child is the first explicit point
      | some parentRanges => 
        -- PIGGYBACK CHECK:
        -- Lean's elaborator assigns the parent's selection range to implicit constructors (e.g. .mk).
        -- If the child's name occupies the exact same source coordinates as the parent, 
        -- the child's name does not actually exist in the source text.
        ranges.selectionRange.pos != parentRanges.selectionRange.pos

/--
Check if `targetName` is a transitive ancestor of `structName` in the structure hierarchy.
Used to distinguish auto-generated `extends` coercions from hand-written conversion functions.
-/
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

/--
Check if a structure is a typeclass (has `@[class]` attribute) by examining whether its
projection functions are registered with `fromClass = true` in `projectionFnInfoExt`.
This works reliably in out-of-elaboration-context environments where `instanceExtension`
is inaccessible (its `asyncMode=.mainOnly` reads an empty local slot rather than the
accumulated imported state).

Both parent projections (`parentInfo.projFn`) and own field projections (`fieldInfo.projFn`)
carry the `fromClass` flag, so this covers classes with only inherited parents, only own
fields, or both.
-/
private def isClassDeclaration (env : Environment) (structName : Name) : Bool :=
  match getStructureInfo? env structName with
  | none => false
  | some info =>
    (info.parentInfo.any fun p =>
      (env.getProjectionFnInfo? p.projFn).any (·.fromClass))
    ||
    (info.fieldInfo.any fun f =>
      (env.getProjectionFnInfo? f.projFn).any (·.fromClass))

/--
Determine if a name is an auto-generated or manually-written structural parent accessor.
Covers three cases:

1. **Direct parent** (`parentInfo.projFn`): Lean registers direct-field parent accessors here.
2. **Typeclass hierarchy coercion** (`A.toB` where A is a typeclass): Mathlib defines many
   explicit `instance (priority := N) A.toB [A K] : B K := { ... }` coercions that navigate
   the class hierarchy (e.g., `Field.toSemifield`, `CommRing.toCommSemiring`). These are
   never in `parentInfo` (B is not in A's `extends` chain — it's reachable via instance
   synthesis), but they are structural plumbing: every instance of A IS an instance of B by
   construction.  We detect them by requiring that A is a typeclass via `isClassDeclaration`.
   The check avoids over-filtering hand-written conversions like `AlgEquiv.toLinearMap`
   because `AlgEquiv` is a non-class structure.
3. **Indirect/multi-hop extends ancestor** (for non-class structures): The `A.toB` naming
   pattern where B is a transitive ancestor of A in the `extends` hierarchy.
-/
private def isStructureParentAccessor (env : Environment) (name : Name) : Bool :=
  match getStructureInfo? env name.getPrefix with
  | none => false
  | some sinfo =>
    -- Fast path: directly listed as a parent projection
    if sinfo.parentInfo.any (fun p => p.projFn == name) then
      true
    else
      let lastComp := name.getString!
      if lastComp.startsWith "to" && lastComp.length > 2 then
        let stripped := lastComp.toRawSubstring.drop 2 |>.toString
        -- Special case: `A.toOfNatN` (e.g. Zero.toOfNat0, One.toOfNat1).
        -- OfNat<n> is not a registered structure name so the general path below fails,
        -- but these are pure numeric-literal plumbing — filter when A is a structure.
        if stripped.startsWith "OfNat" && stripped.any Char.isDigit then
          (getStructureInfo? env name.getPrefix).isSome
        -- Typeclass hierarchy coercion: `A.toB` where A is a typeclass.
        -- Every typeclass instance of A is definitionally an instance of B, so this
        -- coercion has no mathematical content — it just navigates the instance graph.
        else if isClassDeclaration env name.getPrefix then
          true
        else
          -- Non-class slow path: synthesized coercion for a non-direct extends ancestor.
          let targetName := Name.str Name.anonymous stripped
          match getStructureInfo? env targetName with
          | none => false
          | some _ => isTransitiveStructureAncestor env name.getPrefix targetName
      else
        false

/--
Determine if a constant name represents a mechanical/compiler-generated declaration.
Integrated with the Explicit API check.
-/
public def isMechanicalDeclaration (env : Environment) (name : Name) : Bool :=
  -- 1. Primary Rule: Must be part of the Explicit API
  if !isExplicitAPI env name then
    true
  else
    -- 2. Secondary Rules: Filter known match/equation structures natively
    if Lean.Meta.isMatcherCore env name || Lean.Meta.Match.isMatchEqnTheorem env name then
      true
    -- 3. Filter auto-generated parent accessors from `extends` (e.g. `A.toB`)
    else if isStructureParentAccessor env name then
      true
    else
      false

/--
Get the "parent" declaration for a mechanical/auto-generated declaration.
Used to preserve logical connections during filtering.
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
Detect if a name is likely a typeclass instance.
Catches auto-generated instance names (`instFoo`, `Bar.instFoo`) used by Lean's
instance resolution machinery. Not based on the instance table because many core
instances (from Init.*) are registered before the extension system is active,
and because `instanceExtension.instanceNames` is inaccessible via `getState` in
our out-of-elaboration environment context (the instance extension uses `asyncMode=.mainOnly`
which reads an empty local slot rather than the imported accumulated state).
-/
public def isLikelyInstance (name : Name) : Bool :=
  let s := name.toString
  s.startsWith "inst" || (s.splitOn ".inst").length > 1

/--
Determine if a constant belongs to tactic infrastructure that should not appear in
mathematical dependency graphs.

These constants appear in proof terms as artifacts of how tactics like omega, grind,
ring, norm_num, aesop etc. work (proof-by-reflection, internal lemmas, encoding
infrastructure) rather than as genuine mathematical dependencies.

When a tactic-internal constant is encountered during graph construction, it is dropped
entirely — we do NOT expand through it to find mathematical deps underneath, because
by design these nodes don't have meaningful mathematical content to surface.
-/
public def isTacticInternal (name : Name) : Bool :=
  -- Lean core tactic infrastructure (omega, grind, RArray encoding)
  (`Lean.Grind).isPrefixOf name ||
  (`Lean.Omega).isPrefixOf name ||
  (`Lean.RArray).isPrefixOf name ||
  -- Lean elaboration/meta infrastructure (should not appear in math proofs)
  (`Lean.Meta).isPrefixOf name ||
  (`Lean.Elab).isPrefixOf name ||
  (`Lean.Core).isPrefixOf name ||
  (`Lean.Server).isPrefixOf name ||
  (`Lean.Lsp).isPrefixOf name ||
  -- Int/Nat linear arithmetic encoding used by omega
  (`Int.Linear).isPrefixOf name ||
  (`Nat.Linear).isPrefixOf name ||
  (`Nat.ToInt).isPrefixOf name ||
  -- Mathlib tactic layer (ring, norm_num, reassoc, etc.)
  (`Mathlib.Tactic).isPrefixOf name ||
  (`Mathlib.Meta).isPrefixOf name ||
  -- Std tactic infrastructure
  (`Std.Internal).isPrefixOf name ||
  (`Std.Tactic).isPrefixOf name ||
  (`Std.Sat).isPrefixOf name ||
  -- External tactic packages
  (`Aesop).isPrefixOf name ||
  (`Qq).isPrefixOf name

/-- Check if a constant should be included in dependency graphs based on tier. -/
public def shouldIncludeConstant (env : Environment) (name : Name)
    (tier : FilterTier := .standard) (includeInstances : Bool := false) : CoreM Bool := do

  if name.isInternalDetail then return false

  match tier with
  | .exhaustive => return true

  | .standard =>
    -- Category 1 & 2: compiler artifacts and structural plumbing
    if isMechanicalDeclaration env name then return false
    if isAuxRecursor env name || isNoConfusion env name ||
       Lean.Meta.isMatcherCore env name then
      return false
    -- Category 2b: all projection functions (field accessors like Mul.mul, Norm.norm,
    -- CategoryStruct.comp). Bodies are pure field accesses; the parent class is an inductInfo
    -- excluded from proof deps. No exceptions — projections are uniformly filtered.
    if isProjectionFn env name then return false

    -- Category 3: typeclass instances (pragmatic noise filter)
    if !includeInstances && isLikelyInstance name then return false

    -- Category 4: tactic internals (principled — no mathematical content underneath)
    if isTacticInternal name then return false

    return true

/-- Check if a constant should be included in proof dependency graphs. -/
public def shouldIncludeConstantInProofDeps (env : Environment) (name : Name) 
    (tier : FilterTier := .standard) (includeInstances : Bool := false) : CoreM Bool := do
  
  -- Use the general include check (which already uses isExplicitAPI)
  let generalInclude ← shouldIncludeConstant env name tier includeInstances
  if !generalInclude then return false
  
  -- The generalInclude check already covers isExplicitAPI (no range/piggyback).
  -- We only need to check for specific logical types that shouldn't be in proof deps.
  if let some info := env.find? name then
    match info with
    | .inductInfo _ | .opaqueInfo _ | .quotInfo _ => return false
    | .axiomInfo _ => return true
    | _ => return true
  else
    return false

/--
Apply filtering to a dependency list.
Uses an iterative DFS to expand filtered/mechanical nodes (like match blocks) 
so we don't lose the actual mathematical theorems called inside them.
-/
public def applyFiltering (env : Environment) (deps : Array Name) 
    (tier : FilterTier := .standard) (includeInstances : Bool := false) (isProof : Bool := false) : CoreM (Array Name) := do
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
      
      let shouldInclude ← 
        if isProof then 
          shouldIncludeConstantInProofDeps env dep tier includeInstances
        else
          shouldIncludeConstant env dep tier includeInstances
          
      if shouldInclude then
        if !resultSeen.contains dep then
          result := result.push dep
          resultSeen := resultSeen.insert dep
      else
        -- 1. Redirect to parent (e.g. ContinuousLinearMap.mk -> ContinuousLinearMap)
        let parent := getParentDeclaration env dep
        if parent != dep && env.contains parent then
          let parentOk ← if isProof then shouldIncludeConstantInProofDeps env parent tier includeInstances else shouldIncludeConstant env parent tier includeInstances
          if parentOk && !resultSeen.contains parent then
            result := result.push parent
            resultSeen := resultSeen.insert parent
            
        -- 2. Expand the filtered node's body to find real mathematical content inside it
        -- (e.g. an equation lemma wraps the actual recursive call — we want that to surface).
        -- Do NOT expand through:
        --   * Projections (Cat. 2): bodies are pure field accesses with no mathematical content.
        --   * Structural parent accessors (Cat. 2): `A.toB` bodies are `{ ‹A K› with }`.
        --   * Typeclass instances (Cat. 3): bodies contain instance prerequisites, not theorem deps.
        --   * Tactic internals (Cat. 4): no mathematical content underneath by design.
        if isProof && !isProjectionFn env dep && !isStructureParentAccessor env dep && !isLikelyInstance dep && !isTacticInternal dep then
          if let some info := env.find? dep then
            let subDeps := match info with
              | .thmInfo val => val.value.getUsedConstants
              | .defnInfo val => val.value.getUsedConstants
              | _ => #[]
            for subDep in subDeps do
              stack := stack.push subDep
  
  return result

-- Deprecated: use applyFiltering for performance
public def applyTransitiveClosure (env : Environment) (deps : Array Name) 
    (tier : FilterTier := .standard) (includeInstances : Bool := false) : CoreM (Array Name) := 
  applyFiltering env deps tier includeInstances false

-- Deprecated: use applyFiltering for performance
public def applyTransitiveClosureForProofDeps (env : Environment) (deps : Array Name) 
    (tier : FilterTier := .standard) (includeInstances : Bool := false) : CoreM (Array Name) := 
  applyFiltering env deps tier includeInstances true

end Lean.Environment
