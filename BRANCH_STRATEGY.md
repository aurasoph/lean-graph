# Lean-Graph Multi-Version Branch Strategy

## Overview

This repository maintains parallel branches for different Lean 4 versions to support the evolving Lean ecosystem. Each branch is configured for a specific Lean toolchain version.

## Branch Structure

| Branch | Lean Version | Status | Notes |
|--------|--|--------|-------|
| `main` | v4.29.0 | ✅ **Recommended** | Latest stable, all features working |
| `lean-v4.29` | v4.29.0 | ✅ **Working** | Graph executable tested & working |
| `lean-v4.28` | v4.28.0 | ✅ **Working** | Graph executable tested & working |
| `lean-v4.27` | v4.27.0 | ✅ **Working** | Graph executable tested & working |
| `lean-v4.26` | v4.26.0 | ✅ **Working** | Graph executable tested & working |
| `lean-v4.25` | v4.25.0 | ✅ **Working** | Graph executable tested & working |
| `lean-v4.24` | v4.24.0 | ✅ **Working** | Graph executable tested & working |

## Compatibility Notes

### v4.29.0 (Primary)
- **Status**: Fully compatible
- **Projects**: mathlib4, cslib, batteries, aesop, ProofWidgets4
- **Features**: All unified graph features, doc comments, module declarations
- **Build**: `lake build ImportGraph` (clean build)

### v4.25-v4.28 (Fully Compatible)
- **Status**: All versions tested and working ✅
- **What works**:
  - Core ImportGraph library compiles cleanly
  - All graph analysis code functional
  - Graph executable builds and generates valid DOT output
- **API compatibility pattern**:
  - `String.trimAscii` doesn't exist in v4.25-v4.26, use `String.trim` instead
  - `String.trimAscii` exists and is correct in v4.27-v4.29
  - Minor String type coercions needed in v4.25-v4.26 (use type annotations)
  - NameSet.union replaced with explicit insert loop across all versions

### v4.24.0 (Fully Compatible)
- **Status**: Library ✅ and executable ✅ both working
- **What works**: 
  - Core ImportGraph library compiles cleanly
  - All graph analysis code (unified, types, proofs, structures) functional
  - Graph executable builds and generates valid DOT output
- **Solution to lean4-cli incompatibility**: 
  - The `lean4-cli` v4.24.0 tag uses `String.copy`, `String.toSlice` APIs that were removed in Lean v4.24.0 final
  - **Fix**: Use `lean4-cli v4.24.0-rc1` instead (was made before those APIs were removed)
- **API adaptation**:
  - Replace `String.trimAscii` with `String.trim` (not available in v4.24.0)
  - NameSet.union replaced with explicit insert loop

## How to Use

### For a v4.29.0 Project (Recommended)

```bash
cd /path/to/project  # e.g., /home/aurasl/projects/lean-repos/mathlib4

# Ensure lake-manifest.json points to correct lean-graph:
# {"type": "path", "dir": "/home/aurasl/projects/import-graph", ...}

# Build unified graph:
lake exe graph --mode unified --to YourModule /output/path/unified.dot
```

### For a v4.24.0 Project

```bash
cd /home/aurasl/projects/import-graph

# Switch to the v4.24 branch:
git checkout lean-v4.24

# Build the graph executable (uses lean4-cli v4.24.0-rc1):
lake build graph

# Switch to your v4.24 project and generate graph:
cd /path/to/v4.24/project
lake exe graph --mode unified --to YourModule /output/path/unified.dot

# Switch lean-graph back to main:
cd /home/aurasl/projects/import-graph
git checkout main
```

### For a v4.25-v4.28 Project

```bash
cd /home/aurasl/projects/import-graph

# Switch to the matching version:
git checkout lean-v4.25  # or lean-v4.26, lean-v4.27, lean-v4.28

# Build the graph executable:
lake build graph

# Switch to your project and generate graph:
cd /path/to/project
lake exe graph --mode unified --to YourModule /output/path/unified.dot

# Switch lean-graph back to main:
cd /home/aurasl/projects/import-graph
git checkout main
```

## Adding Support for New Versions

If a new Lean version is released and a project targets it:

1. Create a new branch: `git branch lean-v4.30`
2. Set toolchain: `echo "leanprover/lean4:v4.30.0" > lean-toolchain`
3. Commit: `git commit -am "Configure for v4.30.0"`
4. Test: `lake build ImportGraph`
5. If it works, it works; if not, backport fixes as needed

## Maintenance Notes

- **Code is shared**: All branches start from the same source; version differences are toolchain-only unless an API incompatibility requires code changes
- **main should track latest**: Keep `main` on the most recent version (currently v4.29.0)
- **Parallel graphs in storage**: Output graphs are stored separately by version: `/home/aurasl/projects/lean-graphs/v4.X.Y/`

## Future: Cross-Version Compatibility Layer

If maintaining multiple versions becomes a maintenance burden, consider:
- A single compatibility wrapper that detects the Lean version and adapts
- Conditional compilation with `#if lean_version >= ...`
- Upstream fixes to standardize APIs across versions
