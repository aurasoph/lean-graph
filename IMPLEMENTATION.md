# Implementation Guide

How the tool actually works: extracting the 6 edge types, filtering logic, and why we made the design choices we did.

## The 6 Edge Types

The unified graph tracks 6 different kinds of relationships. We compute each independently, then merge them.

### Extends — Structure Inheritance

When one structure extends another, we track that relationship. Call `Lean.getStructureInfo?` and read off the parent structures from `info.parentInfo`.

```lean
structure Point extends Prod where
  ...
```

This creates an edge: `Point → Prod`. Useful for understanding class hierarchies and architecture.

---

### Field — Semantic Composition

Structures have fields. We care about what types those fields depend on.

```lean
structure Tree (α : Type) where
  val : α
  left : Option (Tree α)
  right : Option (Tree α)
```

Get all fields (own + inherited), then walk the type of each field's projection function. The projection for `val` has type `Tree α → α`, so we get edges to `α` and `Option`. That type walking finds everything the field depends on.

`Tree` ends up with field edges to `α`, `Option`, and itself (recursively).

---

### Signature — Type Dependencies

Every declaration has a type signature. Walk it and you find all the types it depends on.

```lean
theorem vec_add (v1 v2 : Vector n) : Vector n := ...
```

`vec_add` has signature edges to `Vector` and `Nat` (since `n : Nat`). This is true regardless of what the proof actually does—it's purely about the types in the signature.

Useful for understanding the type API of a module and which theorems bind to which types.

---

### Proof — Theorem Invocations

Theorems have proof bodies. Extract all the declarations used in the proof.

```lean
theorem my_theorem : P := by
  apply lemma_a
  exact lemma_b ...
```

Walk the proof term with `Expr.getUsedConstants`. `my_theorem` gets edges to `lemma_a` and `lemma_b`.

**Gotcha with `irreducible_def`**: Mathlib's `irreducible_def` hides the real body in an opaque `Subtype`. The proof term doesn't show the true dependencies. But Mathlib also auto-generates a `{name}_def` theorem whose type is `name = actual_body_expr`. We walk that type to recover the hidden dependencies.

Good for logical dependency analysis and understanding what breaks if you change a lemma.

---

### Def — Definition Invocations

Definitions have bodies too. Walk them the same way: `Expr.getUsedConstants` on the body.

```lean
def my_func : Result := f (g x)
```

`my_func` has def edges to `f`, `g`, and `x`. This is about computation—what functions does this actually call?

**Proof vs Def**: 
- Proof edges are from theorem proofs (logical stuff that doesn't run)
- Def edges are from definitions (code that actually executes)
- They're both extracted the same way but routed differently for semantic clarity

Useful for optimization and understanding computation order.

---

### DocRef — Docstring Backtick References

Docstrings can mention other declarations using backticks.

```lean
/-- A wrapper around `List.map` that enforces injectivity. -/
def inj_map := ...
```

Parse docstrings for `` `Name `` patterns (single backticks). Skip `` ``code`` `` spans (double backticks). Valid names are Lean identifiers (letters, digits, `.`, `_`, `'`).

`inj_map` gets a docref edge to `List.map`. These are author-asserted relationships—the person documenting the code is explicitly calling out what it relates to.

Useful for following documentation links and understanding domain structure.

## Filtering and Inclusion Criteria

By default, we match the Mathlib documentation exactly. A declaration is included if:
- It's not marked internal (`_private`, `_`, etc.)
- It has a docstring
- It's not compiler-generated cruft

This filters out `eq_N`, `proof_N`, `match_N`, recursors, NoConfusion types, etc. Default mode: ~46k declarations, ~1.1M edges. Human-written code only.

With `--include-aux`, everything goes in: internal, auto-generated, machinery. ~308k declarations, ~8.4M edges. Use this for full refactoring or compliance audits.

See [FILTERING.md](FILTERING.md) for detailed guidance.

## Transitive Closure

After extracting direct dependencies, we compute the transitive closure. If `A` uses `B` and `B` uses `C`, then `A` gets edges to both `B` and `C` (and transitively, everything `C` uses).

This answers the question: "What's the minimal set of declarations needed to support theorem A?" without traversing the graph every time.

If `C` is filtered out, it won't appear as a direct edge, but its dependencies bubble up to `A`.

## Phase Separation Design

We build the graph in 4 phases:

**Phase 1: Symbol Discovery** — Single pass through all declarations. Decide which ones to include (filtering), classify their types (theorem/def/structure/etc), map them to modules. Cache all this in a `SymbolContext` struct.

Why? Classification is expensive. Doing it once and caching is way faster than repeating it during edge building.

**Phase 2: Edge Computation** — Build each edge type independently (parallelizable). Extends, field, signature, proof, def, docref all computed separately.

**Phase 3: Node Merging** — Collect all unique nodes from all 6 edge types.

**Phase 4: Metadata Attachment** — Use the precomputed `SymbolContext` to attach types and modules to the final nodes via fast hash lookups.

## Module Aggregation

Aggregate declaration-level edges to file-level edges. For each declaration edge `A → B`, ask: what modules are they in? Create a module edge. Count how many declaration edges contributed to each module edge.

Output as CSV (spreadsheet analysis) or DOT (graph viz).

Answers the question: "Which files depend on which files?"

## Output Formats

**DOT** — Human-readable graph format. Edges have labels (proof, sig, extends, etc.). Good for visualization and git diffing.

**CSV** — Two files: nodes (name, type, module) and edges (source, target, kind). Spreadsheet-friendly.

**NDJSON** — One JSON object per line. Streaming-friendly for large graphs and Python pipelines:
```json
{"name":"List.map","decl_type":"definition","module":"Mathlib.Data.List.Basic","edges":[...]}
```

## Why We Made These Choices

**Separate proof and def edges**: Both extracted the same way, but routed by source type. Lets users analyze "logical" vs. "computational" dependencies separately.

**Irreducible def recovery**: `irreducible_def` hides the real body, but we recover it via the auto-generated sibling theorem. Keeps the graph accurate.

**Field dependencies via projection types**: More robust than field names alone; captures the actual types involved.

**Transitive closure on everything**: Expensive, but necessary for correct impact analysis.

**Pre-computed symbol context**: Classify types once in phase 1, use fast lookups in phase 2. Much faster than repeated classification.

**Doc-aligned filtering**: Match the Mathlib documentation exactly so the graph and docs stay in sync.

## Performance

Default mode: ~5–10 minutes (46k declarations, 1.1M edges)  
Exhaustive mode: ~30–60 minutes (308k declarations, 8.4M edges)

Large graphs are streamed to NDJSON.

## Future Ideas

- Tag edges with source line or tactic
- Weight edges by usage frequency
- Cross-version diffs to track how dependencies evolve
- Incremental builds for changed declarations
- Extract proof strategies from proof edges

