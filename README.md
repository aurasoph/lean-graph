# Mathlib4 Dependency Graphs

This repository contains complete dependency graphs for [Mathlib4](https://github.com/leanprover-community/mathlib4), generated using the [import-graph](https://github.com/leanprover-community/import-graph) tool.

For documentation on the import-graph tool itself, see the [original repository](https://github.com/leanprover-community/import-graph).

## Graph Files

All graphs are located in the `mathlib_graphs/` directory:

| File | Size | Nodes | Edges | Description |
|------|------|-------|-------|-------------|
| **mathlib_imports.dot** | 3.1M | ~10K | ~27K | Module-level import dependencies |
| **mathlib_structures.dot** | 160K | ~1K | ~1.5K | Typeclass/structure inheritance hierarchy |
| **mathlib_type_deps.dot** | 135M | ~373K | ~1.7M | Type signature dependencies |
| **mathlib_proof_deps.dot** | 544M | ~387K | ~8.2M | Proof body dependencies |

**Note:** Type-deps and proof-deps graphs filter out auto-generated declarations (constructors, field accessors, recursors, equation lemmas, etc.) to include only human-written mathematics. The graphs contain **all of Lean, Std, and Mathlib** combined, representing ~373K human-written constants from the entire proof environment.


## Graph Types Explained

### 1. Imports Graph (`mathlib_imports.dot`)
**Module-level import relationships**

- **Nodes**: Lean modules (e.g., `Mathlib.Data.List.Basic`)
- **Edges**: Module A → Module B means "B imports A"

### 2. Structures Graph (`mathlib_structures.dot`)
**Typeclass and structure inheritance**

- **Nodes**: Structures/classes that extend other structures (e.g., Group, Ring, Field)
- **Edges**: Parent → Child (e.g., `Monoid → Group` means "Group extends Monoid")

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

## License

The graphs themselves are derived from [Mathlib4](https://github.com/leanprover-community/mathlib4), which is licensed under Apache 2.0.

The generation tool is [import-graph](https://github.com/leanprover-community/import-graph), also Apache 2.0.

## Questions or Issues?

For questions about:
- **The graphs in this repository**: Open an issue here
- **The import-graph tool**: See the [original repository](https://github.com/leanprover-community/import-graph)
- **Mathlib itself**: See [Mathlib4 repository](https://github.com/leanprover-community/mathlib4)
