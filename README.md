# Mathlib4 Dependency Graphs

This repository contains complete dependency graphs for [Mathlib4](https://github.com/leanprover-community/mathlib4), generated using the [import-graph](https://github.com/leanprover-community/import-graph) tool.

For documentation on the import-graph tool itself, see the [original repository](https://github.com/leanprover-community/import-graph).

## Graph Files

All graphs are located in the `mathlib_graphs/` directory:

| File | Size | Nodes/Edges | Description |
|------|------|-------------|-------------|
| **mathlib_imports.dot** | 3.1M | 37,415 modules | Module-level import dependencies |
| **mathlib_hierarchy.dot** | 160K | 2,666 typeclasses | Typeclass/structure inheritance hierarchy |
| **mathlib_type_deps.dot** | 192M | ~3M edges | Type signature dependencies |
| **mathlib_proof_deps.dot** | 607M | ~9.5M edges | Proof body dependencies |

## What's Included

These graphs represent **~380,000 theorems, definitions, and structures** from Mathlib4, including:

- ✅ All user-written theorems, lemmas, and definitions
- ✅ Structure and inductive type definitions  
- ✅ Core Lean foundations (Classical.em, funext, propext, etc.)
- ❌ Typeclass instances (filtered for cleaner analysis)
- ❌ Auto-generated declarations (.eq_def, .sizeOf_spec, etc.)
- ❌ Compiler-internal artifacts

All graphs were generated with the `--include-lean` flag to include Core Lean mathematical foundations.

## Graph Types Explained

### 1. Imports Graph (`mathlib_imports.dot`)
**Module-level import relationships**

- **Nodes**: Lean modules (e.g., `Mathlib.Data.List.Basic`)
- **Edges**: Module A → Module B means "B imports A"
- **Use cases**: Understanding project structure, finding circular dependencies

### 2. Hierarchy Graph (`mathlib_hierarchy.dot`)
**Typeclass and structure inheritance**

- **Nodes**: Structures/classes that extend other structures (e.g., Group, Ring, Field)
- **Edges**: Parent → Child (e.g., `Monoid → Group` means "Group extends Monoid")
- **Use cases**: Understanding algebraic structure relationships, visualizing the typeclass hierarchy
- **Visualization**: Small enough to render as a graph!

### 3. Type-Deps Graph (`mathlib_type_deps.dot`)
**Type signature dependencies**

- **Nodes**: All constants (theorems, definitions, types, structures)
- **Edges**: Used → User (if theorem B's *type signature* mentions constant A)
- **Example**: `Nat → Nat.add_comm` (the theorem's type mentions Nat)
- **Use cases**: Understanding type-level dependencies, analyzing which types/interfaces are used together

### 4. Proof-Deps Graph (`mathlib_proof_deps.dot`)
**Proof body dependencies**

- **Nodes**: All constants (theorems, definitions, structures)
- **Edges**: Used → User (if theorem B's *proof* uses theorem A)
- **Example**: `Nat.add_comm → some_theorem` (the proof applies Nat.add_comm)
- **Use cases**: ML training on proof structure, finding fundamental theorems, analyzing proof dependencies

## Size Considerations

The **hierarchy** and **imports** graphs are small enough to visualize directly with Graphviz:

```bash
dot -Tpng mathlib_graphs/mathlib_hierarchy.dot -o hierarchy.png
dot -Tsvg mathlib_graphs/mathlib_imports.dot -o imports.svg
```

The **type-deps** and **proof-deps** graphs are massive (192M and 607M). For these:
- Extract subgraphs around specific theorems/modules
- Compute statistics (degree distribution, centrality measures)
- Use specialized graph analysis tools (NetworkX, Neo4j, etc.)

## Generation Details

Graphs were generated from Mathlib4 using:

```bash
lake exe graph --mode imports --to Mathlib --include-lean mathlib_imports.dot
lake exe graph --mode hierarchy --to Mathlib --include-lean mathlib_hierarchy.dot
lake exe graph --mode type-deps --to Mathlib --include-lean mathlib_type_deps.dot
lake exe graph --mode proof-deps --to Mathlib --include-lean mathlib_proof_deps.dot
```

Generation environment:
- **Mathlib4 version**: [commit hash from lake-manifest.json]
- **Lean version**: v4.29.0
- **Generated**: April 3-4, 2026

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

## Use Cases

### For Machine Learning
- **Proof-deps graph**: Training theorem provers, analyzing proof strategies
- **Type-deps graph**: Learning type system patterns, predicting types
- Focus on mathematical reasoning (instances and boilerplate already filtered)

### For Analysis
- **Imports graph**: Build system optimization, module organization
- **Hierarchy graph**: Understanding Lean's algebraic structure design
- **Proof-deps graph**: Finding most fundamental theorems (high in-degree)
- **Type-deps graph**: Understanding compositional structure

### For Research
- Studying mathematical dependencies in formal mathematics
- Analyzing proof complexity and structure
- Understanding the foundations of Mathlib

## License

The graphs themselves are derived from [Mathlib4](https://github.com/leanprover-community/mathlib4), which is licensed under Apache 2.0.

The generation tool is [import-graph](https://github.com/leanprover-community/import-graph), also Apache 2.0.

## Questions or Issues?

For questions about:
- **The graphs in this repository**: Open an issue here
- **The import-graph tool**: See the [original repository](https://github.com/leanprover-community/import-graph)
- **Mathlib itself**: See [Mathlib4 repository](https://github.com/leanprover-community/mathlib4)
