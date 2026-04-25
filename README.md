# Mathlib4 Dependency Graphs

Dependency graphs for [Mathlib4](https://github.com/leanprover-community/mathlib4), generated with this repository's `graph` tool.

## Interactive Web Explorer

**[Explore online →](https://aurasoph.github.io/lean-graph/)**

| Graph | Nodes | Edges | Online |
|-------|-------|-------|--------|
| **Structures** | ~3.2K | ~9.1K | ✅ |
| **Imports** | ~10K | ~27K | ✅ |
| **Unified** | ~381K | ~16.1M | ❌ local only |

The unified graph is too large to serve from GitHub Pages (~2.8 GB). It is stored in Git LFS and available locally after cloning.

## What is the Unified Graph?

The unified graph combines every type of dependency in Mathlib into a single database. Each node is a declaration that has its own entry in the [Mathlib documentation](https://leanprover-community.github.io/mathlib4_docs/) — the graph and the docs are in 1:1 correspondence.

Six edge types:

| Kind (in DB) | Meaning |
|------|---------|
| `extends` | Structure/class inheritance |
| `field` | Composition via field/parameter (own and inherited fields) |
| `signature` | Type appearing in a signature |
| `proof` | Theorem used in a proof body |
| `def` | Declaration used in a definition body |
| `docref` | Backtick reference (`` `Name ``) in a docstring |

Note: the DOT file (and `--edge-types` flag) uses `sig` as the label for signature edges; `convert_unified.py` maps this to `signature` when importing into the database.

See [docs/FILTERING.md](docs/FILTERING.md) for the full filtering design and [GRAPH_VALIDATION_TESTS.md](GRAPH_VALIDATION_TESTS.md) for specific test cases that define the graph's quality.

## Project Structure

- `ImportGraph/`: Core Lean library for graph construction and filtering.
- `MainGraph.lean`: Source for `lake exe graph`.
- `MainExportStatements.lean`: Source for `lake exe export_statements`.
- `docs/`: Web explorer assets and database conversion scripts.
- `AGENT_GUIDE.md`: Technical guide for querying the databases via Python/SQLite.

## Generating Graphs

Graphs are generated from within a Mathlib4 checkout with this repo wired in as the `importGraph` dependency.

### Quick Start: Generate the Unified Graph

Assuming you have a built Mathlib4 checkout:

```bash
# 1. Set up import-graph dependency in mathlib4
cd /path/to/mathlib4
cat >> lakefile.lean << 'EOF'
require importGraph from "/path/to/lean-graph"
EOF
lake update importGraph
lake build ImportGraph

# 2. Generate the graph
lake exe graph --mode unified --to Mathlib /path/to/lean-graph/mathlib_graphs/unified_graph.dot

# 3. Convert to SQLite database
cd /path/to/lean-graph
python3 docs/convert_unified.py \
  mathlib_graphs/unified_graph.dot \
  mathlib_graphs/unified_graph_nodes.csv \
  docs/data/unified.db

# 4. Browse locally
python3 -m http.server 8000 --directory docs/
# Open http://localhost:8000
```

### Setup

1. Clone Mathlib4 (it needs to be fully built — `lake build` takes several hours the first time):

```bash
git clone https://github.com/leanprover-community/mathlib4
cd mathlib4
lake build
```

2. In `mathlib4/lakefile.lean`, replace the existing `importGraph` require line with a path pointing to this repo:

```lean
require importGraph from "/path/to/lean-graph"
```

3. Update the manifest and build:

```bash
lake update importGraph
lake build ImportGraph
```

After this, `lake exe graph` uses this repo's version.

### Unified graph (recommended)

The unified graph combines all edge types into a single database. Run from inside the `mathlib4` directory:

```bash
cd /path/to/mathlib4

lake exe graph --mode unified --to Mathlib /path/to/lean-graph/mathlib_graphs/unified_graph.dot
```

This produces two files automatically:
- `unified_graph.dot` — edges with kind labels
- `unified_graph_nodes.csv` — node metadata (name, decl_type, module)

Then convert to SQLite:

```bash
cd /path/to/lean-graph
python3 docs/convert_unified.py mathlib_graphs/unified_graph.dot mathlib_graphs/unified_graph_nodes.csv docs/data/unified.db
```

To include only specific edge types:

```bash
lake exe graph --mode unified --edge-types proof,sig,extends --to Mathlib output.dot
```

### Structures and imports graphs

These are the small graphs served online. Run from inside the `mathlib4` directory, outputting into `lean-graph/mathlib_graphs/` with the exact names `convert_to_db.py` expects:

```bash
cd /path/to/mathlib4

lake exe graph --mode structures --to Mathlib /path/to/lean-graph/mathlib_graphs/mathlib_structures.dot
lake exe graph --to Mathlib /path/to/lean-graph/mathlib_graphs/mathlib_imports.dot
```

Then build the databases:

```bash
cd /path/to/lean-graph
python3 docs/convert_to_db.py
# Reads mathlib_graphs/mathlib_structures.dot and mathlib_graphs/mathlib_imports.dot
# Outputs docs/data/structures.db and docs/data/imports.db
```

### Exporting declaration signatures

Export all declaration signatures to JSONL (for LLM-based processing):

```bash
cd /path/to/mathlib4

# Pretty mode: uses Lean's notation unexpanders (+ * ^ instead of instHAdd.hAdd etc.)
# Requires the Lean interpreter — run with `lean --run`, not the compiled binary
lake env lean --run /path/to/lean-graph/MainExportStatements.lean -- --to Mathlib --pretty --output /path/to/lean-graph/docs/data/statements.jsonl
```

Each line: `{"name":"...","module":"...","decl_type":"...","signature":"...","docstring":"..."}`.

### Other flags

```bash
# Exhaustive mode — bypasses the doc-aligned filter, includes compiler-generated declarations
lake exe graph --mode unified --include-aux --to Mathlib output.dot
```

## Running the Web Explorer Locally

```bash
git lfs install
git clone https://github.com/aurasoph/lean-graph
cd lean-graph
python3 -m http.server 8000 --directory docs/
# Open http://localhost:8000
```

The unified graph (too large for GitHub Pages) is fully available in the local server.

## License

Graphs are derived from [Mathlib4](https://github.com/leanprover-community/mathlib4) (Apache 2.0).
Tool source is Apache 2.0.
