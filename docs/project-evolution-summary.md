# Import-Graph Project Evolution

## Overview

This fork of the official [import-graph](https://github.com/leanprover-community/import-graph) tool extends it with **three new graph modes** (hierarchy, type-deps, proof-deps) and includes **pre-generated complete Mathlib4 dependency graphs**.

**Original Tool**: Module-level import analysis  
**This Fork**: Full dependency analysis at theorem/definition level + complete Mathlib graphs

---

## Changes from Upstream

### 1. **New Graph Modes** (3 additions)

| Mode | Purpose | Graph Structure |
|------|---------|-----------------|
| **hierarchy** | Typeclass/structure inheritance | Parent → Child relationships |
| **type-deps** | Type signature dependencies | Constant A → Theorem B (B's type mentions A) |
| **proof-deps** | Proof body dependencies | Theorem A → Theorem B (B's proof uses A) |

### 2. **New Source Files** (~700 lines of Lean code)

**Core Graph Implementations:**
- `ImportGraph/Graph/Hierarchy.lean` - Typeclass hierarchy extraction
- `ImportGraph/Graph/TypeDeps.lean` - Type signature dependency analysis
- `ImportGraph/Graph/ProofDeps.lean` - Proof body dependency analysis
- `ImportGraph/Graph/FilterCommon.lean` - **Filtering of auto-generated declarations**
- `ImportGraph/Graph/Filter.lean` - Scope filtering utilities
- `ImportGraph/Graph/TransitiveClosure.lean` - Graph reduction algorithms

**Modified Files:**
- `MainGraph.lean` - Added CLI flags for new modes
- `ImportGraph/Export/DotFile.lean` - Enhanced DOT export with progress tracking
- `ImportGraphTest/RegressionTests.lean` - Test coverage for new features

### 3. **Pre-Generated Mathlib4 Graphs**

Added `mathlib_graphs/` directory with complete dependency graphs:

| File | Size | Description | Stats |
|------|------|-------------|-------|
| `mathlib_imports.dot` | 3.1M | Module imports | 37,415 modules |
| `mathlib_hierarchy.dot` | 160K | Typeclass hierarchy | 2,666 nodes, 534 roots |
| `mathlib_type_deps.dot` | 137M | Type dependencies | 373K nodes, 1.74M edges |
| `mathlib_proof_deps.dot` | 437M | Proof dependencies | 373K nodes, 6.61M edges |

**Total size:** 577M (stored with Git LFS)

### 4. **Advanced Filtering System**

**Problem:** Lean kernel auto-generates ~49% of all declarations (constructors, field accessors, recursors, equation lemmas, etc.)

**Solution:** Filter using official Lean Environment APIs:
- `Environment.isProjectionFn` - Filters structure field accessors (Point.x, Point.y)
- `Environment.isMatcherCore` - Filters pattern matchers
- `Environment.isAuxRecursor` - Filters recursors (.rec, .casesOn, .brecOn)
- `Environment.isNoConfusion` - Filters no-confusion machinery
- Pattern matching for `.eq_def`, `.sizeOf_spec`, `.ctorIdx` (no APIs exist)

**Impact:**
- Filtered 363,161 auto-generated constants (49.3% of Mathlib)
- Graphs contain only human-written mathematics
- Type-deps: 29% smaller (192M → 137M)
- Proof-deps: 28% smaller (607M → 437M)

### 5. **Performance Optimizations**

**Proof-Deps File I/O Bottleneck Fix:**
- **Before:** Write each edge immediately (9.5M individual writes)
- **After:** Batch writes in 50MB chunks (2.5 hours → 41 minutes)
- **Speedup:** ~3.6x faster for large graphs

**Stack Overflow Prevention:**
- Replaced deep recursion with iterative algorithms
- Handles Mathlib's 373K constants without stack issues

### 6. **CLI Enhancements**

**New Flags:**
```bash
--mode [imports|hierarchy|type-deps|proof-deps]  # Graph type
--include-lean                                    # Include Core.Lean stdlib
--include-instances                               # Include typeclass instances
--scope <module>                                  # Filter to module scope
```

**Example Usage:**
```bash
# Generate proof dependencies for Mathlib
lake exe graph --mode proof-deps --to Mathlib --include-lean output.dot

# Generate hierarchy for specific module
lake exe graph --mode hierarchy --scope Mathlib.Algebra.Ring output.dot
```

### 7. **Documentation Updates**

- **README.md**: Completely rewritten to document Mathlib graphs
- Focus on the 4 graph types and their use cases
- Removed original tool documentation (reference upstream instead)

### 8. **Git Infrastructure**

- `.gitattributes` - Git LFS configuration for large graphs
- `.gitignore` - Updated to allow graph files, ignore docs/

---

## Technical Highlights

### Filtering Strategy Evolution

**Initial approach (commit 480397c):**
- Pattern matching on declaration names (`.mk`, `.rec`, field accessors)
- Problem: Easy to miss auto-generated patterns

**Current approach (commit 87f7d65):**
- Official Lean Environment APIs (ground truth from kernel)
- Minimal pattern matching only where APIs don't exist
- Verified against Mathlib statistics (95% coverage expected)

### Graph Statistics

**Mathlib Official Stats:**
- 127,481 definitions
- 267,492 theorems
- **Total: 394,973 declarations**

**Our Graphs:**
- **373,543 nodes** (95% of official count)
- Difference accounts for filtered instances and auto-generated items

**Validation:** ✅ Graphs correctly represent human-written mathematics

### Dependencies Used

The proof-deps and type-deps modes perform full metaprogramming analysis of:
- Type signatures (via `Lean.Meta.ppExpr`)
- Proof bodies (via `ConstantInfo.value?`)
- Environment traversal (via `Environment.constants.map₁`)
- Expression folding (via `Lean.Expr.foldConsts`)

No external dependencies - pure Lean 4 metaprogramming.

---

## Commit History Summary

**Major Milestones:**

1. **480397c** - Initial draft extending import-graph to new modes
2. **0cf53af** - Fixed module filtering (was filtering by constant prefix)
3. **b53674a** - Unified repeated code
4. **a79881d** - Fixed stack overflow issues
5. **5e27c70** - File I/O bottleneck fix (3.6x speedup)
6. **9568be2** - Extended to Core.Lean and added flags
7. **610c170** - Additional I/O optimizations
8. **b34312c** - Added complete Mathlib graphs with Git LFS
9. **87f7d65** - Enhanced filtering with official Lean APIs
10. **eea8088** - README rewrite (current state)

**Total commits from upstream:** 10 feature commits

---

## Use Cases

These graphs enable:

1. **Machine Learning on Proofs**
   - Proof-deps graph shows theorem → theorem dependencies
   - Type-deps graph shows type-level relationships
   - 373K human-written mathematical statements

2. **Mathematical Discovery**
   - Find all theorems that depend on a key result
   - Trace proof strategies through dependency chains
   - Identify central vs peripheral theorems

3. **Library Analysis**
   - Understand Mathlib structure at fine granularity
   - Find root theorems (no dependencies)
   - Analyze typeclass hierarchy (534 base classes)

4. **Curriculum Planning**
   - Topological sort gives learning order
   - Type-deps shows conceptual prerequisites
   - Proof-deps shows proof technique dependencies

---

## Future Possibilities

- **Visualization tools** for exploring large subgraphs
- **Interactive web interface** for graph navigation
- **Theorem clustering** by proof technique
- **Dependency metrics** (centrality, betweenness, etc.)
- **Comparison across Mathlib versions** (track library evolution)

---

## Statistics at a Glance

| Metric | Value |
|--------|-------|
| New Lean code | ~700 lines |
| New graph modes | 3 (hierarchy, type-deps, proof-deps) |
| Total graph files | 4 (imports + 3 new modes) |
| Graph file size | 577M (Git LFS) |
| Mathlib constants analyzed | 736,702 |
| Auto-generated filtered | 363,161 (49.3%) |
| Human-written mathematics | 373,543 nodes |
| Total edges (all graphs) | ~8.4M edges |
| Generation time (all 4 graphs) | ~65 minutes |
| Speedup from optimizations | 3.6x (proof-deps) |

---

**Repository:** https://github.com/aurasoph/lean-graph  
**Upstream:** https://github.com/leanprover-community/import-graph  
**License:** Apache 2.0
