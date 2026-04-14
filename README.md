# Mathlib4 Dependency Graphs

Dependency graphs for [Mathlib4](https://github.com/leanprover-community/mathlib4), generated with this repository's `graph` tool.

## Interactive Web Explorer

**[Explore online →](https://aurasoph.github.io/lean-graph/)**

| Graph | Online | Nodes | Edges |
|-------|--------|-------|-------|
| **Structures** | ✅ | ~3.2K | ~9.1K |
| **Imports** | ✅ | ~10K | ~27K |
| **Unified** | ✅ (loads from release) | ~321K | ~8.25M |
| **Type-Deps** | ❌ local only | — | — |
| **Proof-Deps** | ❌ local only | — | — |

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
```

## Running the Web Explorer Locally

To explore large graphs (type-deps, proof-deps) in the browser:

```bash
# 1. Generate the DOT file (see above), e.g. type-deps.dot

# 2. Convert to SQLite — place output at docs/data/<graph-type>.db
#    The script in docs/convert_to_db.py reads from ../mathlib_graphs/ by default;
#    edit the paths in that script or write a short conversion script. Schema:
#      nodes(id TEXT, label TEXT, full_name TEXT)
#      edges(source TEXT, target TEXT)

# 3. Serve the docs/ directory
python3 -m http.server 8000 --directory docs/

# 4. Open http://localhost:8000
```

## License

Graphs are derived from [Mathlib4](https://github.com/leanprover-community/mathlib4) (Apache 2.0).
Tool source is Apache 2.0.
