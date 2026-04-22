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

Note: the DOT file uses `sig` as the edge label for signature edges; `convert_unified.py` maps this to `signature` when importing into the database.

See [docs/FILTERING.md](docs/FILTERING.md) for the full filtering design.

## Generating Graphs Locally

Graphs are generated from within a Mathlib4 checkout that has this repo as a dependency. The `mathlib4` repo at [leanprover-community/mathlib4](https://github.com/leanprover-community/mathlib4) already includes it — or add it to your own lakefile:

```lean
require importGraph from "/path/to/import-graph"
```

Then run from inside the `mathlib4` directory:

```bash
cd /path/to/mathlib4

# Structures (typeclass/structure hierarchy)
lake exe graph --mode structures --to Mathlib output.dot

# Module-level imports
lake exe graph --to Mathlib output.dot

# Type signature dependencies
lake exe graph --mode type-deps --to Mathlib output.dot

# Proof body dependencies
lake exe graph --mode proof-deps --to Mathlib output.dot

# Unified (all edge types combined)
lake exe graph --mode unified --to Mathlib output.dot

# Unified — specific edge types only
lake exe graph --mode unified --edge-types proof,extends --to Mathlib output.dot

# Exhaustive mode (bypasses doc-aligned filter, includes everything)
lake exe graph --mode unified --include-aux --to Mathlib output.dot
```

## Running the Web Explorer Locally

The database files are included in this repo via Git LFS. To run locally:

```bash
git lfs install
git clone https://github.com/aurasoph/lean-graph
cd lean-graph
python3 -m http.server 8000 --directory docs/
# Open http://localhost:8000
```

The unified graph (too large for GitHub Pages) is fully available in the local server.

### Regenerating databases

If you've generated a fresh DOT file and want to rebuild the databases:

**Structures, imports** — place DOT files in `mathlib_graphs/`, then:

```bash
python3 docs/convert_to_db.py
# Reads from ../mathlib_graphs/*.dot, outputs to docs/data/<graph-name>.db
```

**Unified** — uses `convert_unified.py`, which reads the DOT file and its companion nodes CSV (written automatically alongside the DOT) and produces a DB with two tables:
- `nodes(name TEXT, decl_type TEXT, module TEXT)` — declaration kind and defining module
- `edges(src TEXT, dst TEXT, kind TEXT)` — edges with kind: `extends`, `field`, `sig`, `proof`, `def`, `docref`

```bash
# Generates unified_graph.dot + unified_graph_nodes.csv
lake exe graph --mode unified --to Mathlib unified_graph.dot

python3 docs/convert_unified.py unified_graph.dot unified_graph_nodes.csv docs/data/unified.db
```

**Exporting declaration signatures** — export all declaration signatures to JSONL for LLM-based processing:

```bash
# Run from inside your Mathlib checkout (compiled binary, fast)
lake exe export_statements --to Mathlib --output statements.jsonl
# Produces: {"name":"...","module":"...","decl_type":"...","signature":"...","docstring":"..."}

# Pretty mode: activates notation unexpanders (+ * ^ instead of instHAdd.hAdd etc.)
# Requires the Lean interpreter — run with `lean --run`, not the compiled binary
lake env lean --run /path/to/MainExportStatements.lean -- --to Mathlib --pretty --output statements_pretty.jsonl

# Exhaustive mode (includes everything, bypasses filter)
lake exe export_statements --include-aux --to Mathlib --output statements.jsonl
```

## License

Graphs are derived from [Mathlib4](https://github.com/leanprover-community/mathlib4) (Apache 2.0).
Tool source is Apache 2.0.
