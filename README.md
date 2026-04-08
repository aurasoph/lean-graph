# Mathlib4 Dependency Graphs

This repository contains complete dependency graphs for [Mathlib4](https://github.com/leanprover-community/mathlib4), generated using the [import-graph](https://github.com/leanprover-community/import-graph) tool.

## 🌐 Interactive Web Explorer

**[Explore the graphs online →](https://aurasoph.github.io/lean-graph/)**

Browse dependency relationships with an interactive web interface:
- **Search Mode**: Build custom neighborhoods by clicking nodes  
- **Traversal Mode**: Navigate step-by-step through dependencies
- Available online: Structures (1.6K nodes) and Imports (10K nodes)
- [Local setup](#local-web-explorer) required for large graphs (type-deps: 373K nodes, proof-deps: 387K nodes)

For documentation on the import-graph tool itself, see the [original repository](https://github.com/leanprover-community/import-graph).

## Graph Files

All graphs are located in the `mathlib_graphs/` directory:

| File | Size | Nodes | Edges | Description |
|------|------|-------|-------|-------------|
| **mathlib_imports.dot** | 3.1M | ~10K | ~27K | Module-level import dependencies |
| **mathlib_structures.dot** | 836K | 4,897 | 8,503 | Typeclass/structure inheritance hierarchy (with field dependencies) |
| **mathlib_type_deps.dot** | 135M | ~373K | ~1.7M | Type signature dependencies |
| **mathlib_proof_deps.dot** | 544M | ~387K | ~8.2M | Proof body dependencies |

**Note:** Type-deps and proof-deps graphs filter out auto-generated declarations (constructors, field accessors, recursors, equation lemmas, etc.) to include only human-written mathematics. The graphs contain **all of Lean, Std, and Mathlib** combined, representing ~373K human-written constants from the entire proof environment.


## Graph Types Explained

### 1. Imports Graph (`mathlib_imports.dot`)
**Module-level import relationships**

- **Nodes**: Lean modules (e.g., `Mathlib.Data.List.Basic`)
- **Edges**: Module A → Module B means "B imports A"

### 2. Structures Graph (`mathlib_structures.dot`)
**Typeclass and structure inheritance with field dependencies**

- **Nodes**: All structures with any relations (4,897 nodes)
  - Structures with parent structures (extends relationships)
  - Structures with field/parameter dependencies
  - Structures that are referenced by others
- **Edges**: Parent → Child, including both `extends` relationships AND field/parameter dependencies
  - Example: `Monoid → Group` (Group extends Monoid)
  - Example: `TopologicalSpace → T0Space` (T0Space has TopologicalSpace as parameter)
  - Example: `Group → NormedGroup` (NormedGroup has Group as a field)
- **Includes**: Leaf nodes (structures referenced by others but with no dependencies themselves)

### 3. Type-Deps Graph (`mathlib_type_deps.dot`)
**Type signature dependencies**

- **Nodes**: Human-written constants (theorems, definitions, types, structures)
- **Edges**: Used → User (if theorem B's *type signature* mentions constant A)
- **Example**: `Nat → Nat.add_comm` (the theorem's type mentions Nat)
- **Filtering**: Excludes auto-generated declarations (field accessors, recursors, pattern matchers, etc.)

### 4. Proof-Deps Graph (`mathlib_proof_deps.dot`)
**Proof body dependencies**

- **Nodes**: Human-written constants (theorems, definitions, structures)
- **Edges**: Used → User (if theorem B's *proof* uses theorem A)
- **Example**: `Nat.add_comm → some_theorem` (the proof applies Nat.add_comm)
- **Filtering**: Excludes auto-generated declarations (same as type-deps)
- **Use case**: Most valuable for understanding proof strategies and theorem dependencies

## Generation Details

Graphs were generated from within the Mathlib4 repository using the import-graph tool:

```bash
# From within mathlib4/ directory:
lake exe graph --mode imports --to Mathlib --include-lean mathlib_imports.dot
lake exe graph --mode structures --to Mathlib --include-lean mathlib_structures.dot
lake exe graph --mode type-deps --include-lean mathlib_type_deps.dot
lake exe graph --mode proof-deps --include-lean mathlib_proof_deps.dot
```

**Key flags:**
- `--include-lean`: Include Lean standard library and Std library (not just Mathlib)
- `--to Mathlib`: For imports/structures graphs, focus on Mathlib modules
- Without `--to`: For type-deps/proof-deps, includes all constants from the entire environment (Lean + Std + Mathlib)

This produces graphs containing the complete proof environment, not just Mathlib-specific content.

## Local Web Explorer

For the complete interactive experience including large graphs:

### Prerequisites
- Python 3.6+
- Git

### Setup
```bash
# 1. Clone and setup
git clone https://github.com/aurasoph/lean-graph.git
cd lean-graph/web-explorer

# Note: Large files (type-deps: 431MB, proof-deps: 1.9GB) download via Git LFS
# The clone may take several minutes depending on connection speed

# 2. Generate databases (creates SQLite .db files from DOT files)
python3 convert_to_db.py

# 3. Start local web server  
python3 -m http.server 8000

# 4. Open in browser
open http://localhost:8000
```

This provides access to all four graph types with efficient SQLite-based querying:
- **Structures** (487KB database) - Typeclass inheritance hierarchy
- **Imports** (8.8MB database) - Module dependencies  
- **Type-deps** (431MB database) - Type signature dependencies
- **Proof-deps** (1.9GB database) - Proof body dependencies

### Alternative JSON Format
```bash
# Generate JSON files instead (for compatibility)
python3 convert_to_json.py
```

## File Format

All files use the [DOT graph description language](https://graphviz.org/doc/info/lang.html) (Graphviz format):

```dot
digraph "import_graph" {
  "node_name" [attributes];
  "source" -> "target";
}
```

This is a text-based format that can be:
- Parsed programmatically
- Visualized with Graphviz tools
- Analyzed with graph libraries (NetworkX, igraph, etc.)
- Converted to other formats (GraphML, JSON, etc.)

## Regenerating Mathlib Graphs

To reproduce the graphs in `mathlib_graphs/`, run these commands exactly.

### Flag Explanations
*   `--to Mathlib`: Limit graph to nodes defined within the Mathlib package.
*   `--include-deps`: Include dependencies from other packages (Aesop, Std, etc.).
*   `--include-lean`: Include core Lean types (Nat, Eq, List, etc.) from `Init` and `Lean`.

### Exact Commands
```bash
# 1. Structures Graph
lake exe graph --mode structures --to Mathlib --include-lean --include-deps mathlib_structures.dot

# 2. Imports Graph
lake exe graph --to Mathlib --include-lean --include-deps mathlib_imports.dot

# 3. Type-Deps Graph (Blueprint)
lake exe graph --mode type-deps --to Mathlib --include-lean --include-deps mathlib_type_deps.dot

# 4. Proof-Deps Graph (Logic)
lake exe graph --mode proof-deps --to Mathlib --include-lean --include-deps mathlib_proof_deps.dot

# 5. Unified Graph
lake exe graph --mode unified --to Mathlib --include-lean --include-deps mathlib_unified.dot
```

Generation of `proof-deps` for full Mathlib can take significant time. Other graph modes are much faster.

## License

The graphs themselves are derived from [Mathlib4](https://github.com/leanprover-community/mathlib4), which is licensed under Apache 2.0.

The generation tool is [import-graph](https://github.com/leanprover-community/import-graph), also Apache 2.0.

## Questions or Issues?

For questions about:
- **The graphs in this repository**: Open an issue here
- **The import-graph tool**: See the [original repository](https://github.com/leanprover-community/import-graph)
- **Mathlib itself**: See [Mathlib4 repository](https://github.com/leanprover-community/mathlib4)
