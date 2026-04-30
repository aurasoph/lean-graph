# Graph Filtering Guide

## Overview

The import-graph tool filters declarations by default to focus on **human-written, documented code**. This produces a cleaner, more meaningful dependency graph. However, you can see the complete graph including all auto-generated and internal machinery.

## Default Filtering (Recommended for Analysis)

By default, ~46k declarations are included:

```bash
lake exe graph --to Mathlib --mode unified output.dot
```

**What's filtered out:**
- Auto-generated declarations (`eq_N`, `proof_N`, `match_N`, `omega_N`)
- Internal/private declarations (prefixed with `_private` or `_`)
- Compiler machinery (raw recursors, NoConfusion types, matchers)
- Auxiliary recursors and other internal helpers
- Non-explicit API (declarations without source documentation range)

**Characteristics:**
- ~46k nodes in Lean+Std
- ~1.1M edges across 6 semantic types
- Focuses on mathematical and user-facing content
- Clean for understanding code structure and dependencies

**Use cases:**
- Understanding module architecture
- Mathematical dependency analysis
- Refactoring planning within human code
- Identifying which libraries/functions matter

## Exhaustive Mode (All Declarations)

Include everything including compiler-generated and internal machinery:

```bash
lake exe graph --to Mathlib --mode unified --include-aux output.dot
```

**What's included:**
- All auto-generated declarations (300k+ total in Mathlib)
- Private/internal declarations
- Compiler machinery and recursors
- Instance machinery and type class scaffolding
- Everything Lean generates or synthesizes

**Characteristics:**
- ~308k nodes (6.7x larger)
- ~8.4M edges (7.6x more edges)
- Includes all transitive dependencies
- Shows complete picture of how Lean builds up the system

**Use cases:**
- Full codebase refactoring (need to move everything)
- Compliance/audit (need to see all dependencies)
- Understanding Lean's internal machinery
- Migration planning (moving between versions)
- Analyzing mechanical patterns in generated code

## Comparison: Filtered vs. Exhaustive

| Aspect | Filtered (Default) | Exhaustive (`--include-aux`) |
|--------|-------------------|------------------------------|
| **Scope** | Human-written code | Everything (human + generated) |
| **Nodes** | 46k | 308k (6.7x) |
| **Edges** | 1.1M | 8.4M (7.6x) |
| **Best for** | Analysis, understanding | Refactoring, audits, internals |
| **Noise level** | Low | High (lots of machinery) |
| **Edge types** | 6 semantic types | All dependencies lumped together |
| **Documentation** | All nodes have source docs | Many nodes auto-generated |

## Examples

### Example 1: Understand Nat dependencies
```bash
# Clean view: what mathematical code depends on Nat
lake exe graph --to Mathlib --mode unified --edge-types proof,sig output.dot

# Exhaustive: see every last place Nat is used, including internals
lake exe graph --to Mathlib --mode unified --include-aux --edge-types proof,sig output.dot
```

### Example 2: Refactoring impact
```bash
# Before refactoring, see what must move together
lake exe graph --to Mathlib --mode unified --include-aux output.dot

# Understand the mathematical dependencies
lake exe graph --to Mathlib --mode unified output.dot
```

### Example 3: Compliance/audit
```bash
# Full picture: all dependencies and their sources
lake exe graph --to Mathlib --mode unified --include-aux output.ndjson
# Then analyze in Python/SQL to track all usage
```

## Edge Semantics (Filtered Mode Only)

The filtered graph includes 6 semantic edge types. Exhaustive mode doesn't distinguish:

- **extends**: Structure inheritance
- **field**: Field/parameter type references
- **sig**: Types appearing in declarations
- **proof**: Invocations in proof bodies
- **def**: Invocations in definitions
- **docref**: Backtick references in docstrings

This helps answer: "Why does X depend on Y?" The exhaustive graph doesn't make this distinction.

## Filtering Details

The filtering matches [doc-gen4](https://github.com/leanprover-community/doc-gen4)'s visible API definition:
- A node is included iff it would appear as a standalone entry in the Lean docs
- Auto-generated "ghost" children are excluded
- Internal details and private declarations are excluded

## Performance Notes

- **Filtered graphs** process faster (46k declarations)
- **Exhaustive graphs** are slower (308k declarations + 7.6x edges)
- **NDJSON format** is streaming-friendly for both
- **DOT format** produces very large files in exhaustive mode

For large graphs, consider:
- Using `--aggregate module` for module-level view
- Filtering by `--edge-types` to reduce edges
- Using `--from` or `--to` flags to focus on sub-graphs
