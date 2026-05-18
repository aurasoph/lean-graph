# Mathlib Dependency Analysis via Lean Metaprogramming

Extracts the complete dependency structure of Mathlib by walking Lean's compiled kernel environment. You get a queryable graph where each node is a documented declaration and edges represent 6 kinds of dependencies: inheritance, fields, type signatures, proof invocations, definitions, and docstring references.

## Interactive Web Explorer

**[Explore online →](https://aurasoph.github.io/lean-graph/)**

| Graph | Nodes | Edges | Available |
|-------|-------|-------|-----------|
| **Structures** | ~3.2K | ~9.1K | ✅ Online |
| **Imports** | ~10K | ~27K | ✅ Online |
| **Unified** | ~46K | ~1.1M | ✅ Local (> 2.8 GB) |

## How It Works

Instead of parsing source text, this runs as a **Lean metaprogram inside the `CoreM` monad** and directly inspects Lean's compiled kernel environment. 

It walks `Lean.Environment.constants` to find all declarations, inspects their metadata (via `ConstantInfo` variants like `.thmInfo`, `.defnInfo`, `.inductInfo`), and extracts dependencies by reading proof bodies and definitions with `Expr.getUsedConstants`. Type signatures get walked for transitive type dependencies. Structure inheritance and field composition come from `Meta.getStructureInfo?` and `isClass`. Docstrings are parsed for backtick references.

Finally, it applies the same doc-gen4 filter that governs the Mathlib docs — so the graph and documentation stay in perfect 1:1 correspondence. Result: a queryable graph where edges capture 6 kinds of semantic relationships.

## The Unified Graph

Combines all 6 edge types into one queryable database:

| Edge Type | Meaning |
|-----------|---------|
| `extends` | Structure inheritance |
| `field` | Field composition |
| `sig` | Type signatures |
| `proof` | Proof invocations |
| `def` | Definition invocations |
| `docref` | Docstring references |

By default, you get ~321k declarations (human-written code only). With `--include-aux`, you get all declarations including compiler machinery.

### Node schema (NDJSON)

Each line of the NDJSON file is one JSON object:

```json
{
  "name":        "Finset.sum",
  "decl_type":   "def",
  "module":      "Mathlib.Algebra.BigOperators.Group.Finset",
  "in_degree":   4201,
  "is_instance": false,
  "docstring":   "The sum of `f x` as `x` ranges over `s`.",
  "edges":       [ ... ]
}
```

| Field | Type | Description |
|-------|------|-------------|
| `name` | string | Fully qualified Lean declaration name |
| `decl_type` | string | `def`, `thm`, `inst`, `axiom`, `opaque`, `inductive`, `structure`, `class` |
| `module` | string | Lean module the declaration is defined in |
| `in_degree` | int | Number of other declarations that reference this one |
| `is_instance` | bool | Whether the declaration is a registered typeclass instance |
| `docstring` | string | Docstring text, or empty string |
| `edges` | array | Outgoing dependency edges (see below) |

### Edge schema

Each entry in the `edges` array:

```json
{
  "target":   "Finset",
  "kind":     "sig",
  "position": "hyp",
  "binder":   "explicit",
  "role":     "fn",
  "via_proj": false
}
```

| Field | Present on | Values | Description |
|-------|-----------|--------|-------------|
| `target` | all | string | Name of the dependency |
| `kind` | all | `sig` `proof` `def` `extends` `field` `docref` | Relationship type |
| `position` | `sig` | `hyp` `conclusion` | Whether the dep appears in a hypothesis or the return type |
| `binder` | `sig`/`hyp` | `explicit` `implicit` `inst` `strict` | How the argument is bound |
| `role` | `sig` | `fn` `arg` | Whether the dep is in function or argument position |
| `via_proj` | `sig` | bool | Whether the dep is accessed via a field projection |

See [FILTERING.md](docs/FILTERING.md) for detailed guidance on which mode to use.

## Regenerating the Unified Graph

To rebuild the graph against a fresh Mathlib4 checkout:

### 1. Set up the dependency

From inside a fully-built Mathlib4 repository:

```bash
cd /path/to/mathlib4

# Add this repo as a local dependency
cat >> lakefile.lean << 'EOF'
require importGraph from "/path/to/import-graph"
EOF

# Build the library
lake build ImportGraph
```

### 2. Generate the graph

```bash
lake exe graph --mode unified --to Mathlib /path/to/import-graph/output/unified_graph.dot
```

This produces:
- `unified_graph.dot` — graph edges with semantic labels
- `unified_graph_nodes.csv` — node metadata (name, declaration type, module)

### 3. Convert to SQLite

```bash
cd /path/to/import-graph

python3 docs/convert_unified.py \
  output/unified_graph.dot \
  output/unified_graph_nodes.csv \
  docs/data/unified.db
```

### 4. Browse locally

```bash
python3 -m http.server 8000 --directory docs/
# Open http://localhost:8000
```

**Optional: Include specific edge types only**

```bash
lake exe graph --mode unified --edge-types proof,sig,extends --to Mathlib output.dot
```

## Other graph formats

The tool also outputs module-level aggregations and import-only graphs:

```bash
# Module architecture (file-level dependencies)
lake exe graph --mode unified --aggregate module mathlib_modules.csv

# Import structure (file imports only)
lake exe graph --to Mathlib mathlib_imports.dot

# Fine-grained structures (inheritance and composition)
lake exe graph --mode structures --to Mathlib mathlib_structures.dot
```

For data analysis, use NDJSON format:

```bash
lake exe graph --mode unified --to Mathlib output.ndjson
```

See [FILTERING.md](docs/FILTERING.md) and `lake exe graph --help` for all options.

## License

Graphs are derived from [Mathlib4](https://github.com/leanprover-community/mathlib4) (Apache 2.0).
Tool source is Apache 2.0.
