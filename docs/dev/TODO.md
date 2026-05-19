# TODO

## Fix `getParentDeclaration` spurious prefix edges

**File:** `LeanGraph/Graph/FilterCommon.lean`

### Symptom

Phantom `proof` (and `def`) edges from Prop-valued field projectors to whatever
constant happens to share the projector's enclosing namespace name. Surfaced by
the 17-node SCC in `Mathlib.CategoryTheory.Presentable.Directed` that closes
through `Diagram.hP → CategoryTheory.IsCardinalFiltered.exists_cardinal_directed`.
The latter is the main lemma at line 528; the structure `Diagram` is defined at
line 65, so the edge is impossible in any semantic reading.

### Root cause

`getParentDeclaration` (FilterCommon.lean:110) falls through for anything that
isn't a `.ctorInfo` or `.recInfo`:

```lean
| _ => name.getPrefix
```

When `Diagram.hP`'s body references the structure `...exists_cardinal_directed.Diagram`,
that constant is filtered out of proof deps (structures are excluded). The
parent fallback strips `.Diagram`, lands on `...exists_cardinal_directed`, finds
that name happens to exist in the env (the lemma) and adds it as a proof edge.

The cycle requires three things to coincide:
1. Prop-valued projectors classified as `theorem` (legitimate Lean behavior)
2. A namespace and a lemma sharing a name (`namespace foo` + `lemma foo` —
   common in Mathlib)
3. The prefix-fallback in `getParentDeclaration`

(1) and (2) are real Mathlib structure. (3) is our bug.

### Fix: source-range parenting (Option B)

Replace the prefix fallback with a check that the prefix and the filtered name
come from the same source declaration. This is the criterion doc-gen4 uses for
associating aux decls with their parent — and the rest of the tool is already
aligned with doc-gen4.

```lean
public def getParentDeclaration (env : Environment) (name : Name) : CoreM Name := do
  if let some info := env.find? name then
    match info with
    | .ctorInfo val => return val.induct
    | .recInfo val  => return val.name.getPrefix
    | _ =>
      let prefix := name.getPrefix
      let some r1 ← findDeclarationRanges? name | return name
      let some r2 ← findDeclarationRanges? prefix | return name
      if r1.range == r2.range then return prefix else return name
  else return name
```

In `applyFiltering`, only add the parent edge if it differs from `name`
(i.e. we got a real semantic parent).

### Why this approach

- Pure metaprogramming — no regex, no name-string matching.
- Uses the same source-provenance test doc-gen4 uses, so consistent with
  `isExplicitAPI` and the rest of our filter.
- Correctly recovers `Foo` from `Foo._proof_3`, `Foo.eq_1`, `Foo.match_1` (same
  source range), while rejecting `Diagram → exists_cardinal_directed` (different
  source ranges).

### Verification

After the fix:
- Rebuild unified NDJSON against Mathlib v4.29.
- Confirm the 17-node SCC in `CategoryTheory.IsCardinalFiltered.exists_cardinal_directed`
  collapses without any projector filtering.
- Spot-check that legitimate parent edges (e.g. `Foo._proof_N → Foo`) are still
  produced.
- Compare total edge count before/after — expect a small reduction.

### Other SCCs likely affected by the same bug

SCC scan of the proof+def subgraph (188 non-trivial SCCs) shows several large
components with the same bug shape — a root `def` whose name coincides with
the namespace it lives in, and descendants of that namespace ending up with
phantom edges back to the root:

| SCC | Module | Size | Pattern |
|-----|--------|------|---------|
| #2  | `Mathlib.CategoryTheory.Presentable.Directed` | 41 | original cycle, `Diagram.hP → exists_cardinal_directed` |
| #4  | `Mathlib.Algebra.Homology.HomotopyCategory.HomComplex` | 18 | `CochainComplex.HomComplex.Cochain.*` → `CochainComplex` |
| #5  | `Mathlib.GroupTheory.OreLocalization.*` | 11 | `OreLocalization.OreSet.*` → `OreLocalization` |
| #6  | `Mathlib.GroupTheory.OreLocalization.*` | 11 | `AddOreLocalization.AddOreSet.*` → `AddOreLocalization` |
| #9  | `Mathlib.RingTheory.GradedAlgebra.HomogeneousLocalization` | 6 | `HomogeneousLocalization.NumDenSameDeg.*` → `HomogeneousLocalization` |

Genuine mutual blocks that **should** stay cyclic and aren't affected:
SCC #1 (bitblast, 103 nodes), SCC #3 (LRAT.Trim, 19 nodes),
SCC #13 (Subobject.Lattice, 5 nodes).

Aggregate signal across the whole graph: ~89.8k proof/def edges target a
strict name-prefix of the source. Depth-gap breakdown:

| Gap | Count | Interpretation |
|-----|-------|----------------|
| 0   | 79,311 | mostly legit method-on-type references |
| 1   | 9,548  | mixed: real for mutual blocks, bug for namespace-skip chains |
| 2   | 887    | almost all bug |
| 3+  | 46     | bug |

The source-range check in Option B distinguishes these cleanly: in every
artifact case the source and prefix-target sit at unrelated source locations,
whereas legitimate parents (`Foo._proof_N → Foo`, etc.) share a range.

### Cross-module verification scan

Ran an import-direction check on the 10,481 depth≥1 proof/def prefix edges
(where target is a strict name-prefix of source). Verdict if `tgt.module`
imports `src.module` it's impossible (target elaborated after source ⇒ bug);
if `src.module` imports `tgt.module` the edge is plausibly a real direct
reference.

| Verdict | Count |
|---------|-------|
| BUG (cross-module impossible) | 8 |
| SAME_MOD (needs line-number check) | 1,738 |
| REAL_POSSIBLE (src imports tgt) | 7,023 |
| UNRELATED (parser missed imports) | 681 |
| CYCLE? (parser thinks mutual imports) | 1,031 |

The 8 confirmed cross-module bugs are all the OreLocalization /
AddOreLocalization cases (`OreLocalization.OreSet.* → OreLocalization`).
Most bugs are same-module — confirmed via line numbers for
`HomogeneousLocalization.NumDenSameDeg.num_zero → HomogeneousLocalization`
(line 190 → 281), and for the original Directed.lean case via reasoning
about declaration order. The same-module count of 1,738 likely contains the
bulk of remaining bugs; spot-grepping for line numbers fails on auto-generated
projectors (no source line), which is the dominant source decl for this bug.

SCC #4 (HomComplex) verified as **likely real**: `HomComplex` does
transitively import `HomologicalComplex` where `CochainComplex` is defined,
so `Cochain.zero_v → CochainComplex` is a plausible direct reference, not
a prefix-strip artifact. Retract from the bug list.

### Other bug directions worth scanning

These are *not* the same root cause; each needs its own scan and fix.

1. **Aux-expansion overreach.** The DFS-into-body branch in
   `applyFiltering` (FilterCommon.lean:219) walks through filtered nodes to
   surface real content. It can pull constants from unrelated code paths
   inside a matcher or equation block. Scan: proof/def edges where target is
   not a prefix of source AND not in any module the source's module imports.

2. **Decl-type misclassification.** A Prop-valued declaration classified as
   `def` (or a `def` classified as `thm`) routes edges to the wrong category.
   Scan: for every node, fetch its `ConstantInfo` and compare `isProp`
   against the assigned `decl_type`.

3. **`isProjectionFn` / `isStructureParentAccessor` false negatives.** If
   either predicate misses a projector, the expansion at line 219 walks
   through it and leaks unrelated constants. Scan: list all decls passing
   `shouldIncludeConstantInProofDeps` that `getProjectionFnInfo?` recognizes
   as projections.

### Stretch: consider dropping the fallback entirely

Worth testing first: do we even need parent surfacing? The `getUsedConstants`
DFS expansion already recovers content from filtered wrappers (`eq_N`,
`match_N`, `_proof_N` bodies all reference their meaningful internals
directly). If empirical edge coverage is unchanged after removing
`getParentDeclaration` entirely, that's the cleanest fix. The source-range
version is the safe choice if expansion turns out to miss some cases.
