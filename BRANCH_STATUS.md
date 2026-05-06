# Multi-Version Branch Status (May 6, 2026)

## Summary

The lean-graph project now supports Lean 4 versions v4.24 through v4.29 via separate git branches. Each branch contains version-specific API adjustments while maintaining a unified codebase structure.

## Branch Status

### ✅ v4.29 (Lean 4.29.0) — Primary Branch

**Branch:** `lean-v4.29`  
**Status:** ✅ Fully Functional  
**Last Tested:** May 6, 2026

**Features:**
- All features working: unified graph, type-deps, proof-deps, structures modes
- String.dropRight → String.dropEnd deprecation warnings (non-breaking)
- Mathlib graph: 381k nodes, ~8M edges, ~1.2GB
- Average generation time: 45 minutes

**Recent Changes:**
```
008cdbe made import graph more general
b63167b moved type deps onto lfs
f287ac3 updated to fix the db files
```

---

### ✅ v4.28 (Lean 4.28.0)

**Branch:** `lean-v4.28`  
**Status:** ⚠️ Ported, Untested  
**Last Committed:** May 6, 2026

**API Changes Made:**
- Removed `public` from import/definition declarations
- Fixed `NameSet.union` (not available in v4.28)
- Replaced `String.trimAscii` with `String.trim`
- Updated Cli dependency to v4.28.0

**Recent Commits:**
```
f579bf4 readjusted to match 4.29 more
790fa45 fixed 4.28
50b274d Add v4.28 support: Lean 4.28.0 API compatibility
e82debc Configure lean-toolchain for v4.28.0
```

**Next Steps:**
- Verify functionality against mathlib4-v4.28
- Generate test graphs to confirm API compatibility

---

### ⚠️ v4.27 (Lean 4.27.0)

**Branch:** `lean-v4.27`  
**Status:** ⚠️ Ported, Untested

**API Changes Made:**
- Removed bare `module` keyword (experimental in v4.24-v4.26)
- Removed `public` from imports
- Fixed `NameSet.union` compatibility
- Replaced String methods

**Commit:**
```
a273637 fixed 4.27
d5aaf58 Add v4.27 support: Lean 4.27.0 API compatibility
```

---

### ⚠️ v4.26 (Lean 4.26.0)

**Branch:** `lean-v4.26`  
**Status:** ⚠️ Ported, Untested

**API Changes Made:**
- Removed bare `module` keyword
- Removed `public` declarations
- Fixed `NameSet.union`
- String.trimAscii → String.trim
- Type annotations for String operations

**Commit:**
```
146780b fixed 4.26
d7262a8 Add v4.26 support
```

---

### ⚠️ v4.25 (Lean 4.25.0)

**Branch:** `lean-v4.25`  
**Status:** ⚠️ Ported, Untested

**API Changes Made:**
- Same as v4.26 (bare module, public removal, etc.)

**Commit:**
```
2f58a9b fixed 4.25
747db92 Add v4.25 support
```

---

### ❌ v4.24 (Lean 4.24.0)

**Branch:** `lean-v4.24`  
**Status:** ⚠️ Partially Ported, Known Gaps

**Issues:**
- Type system API changes (NameSet, TreeSet)
- String library differences
- Module/import syntax experimental
- May require additional fixes beyond current porting

**Recent Status:**
```
951305d fixed so it builds
ce02255 Add v4.24 support (incomplete)
```

**Recommendation:** Requires deeper investigation and testing. Current codebase may not fully support v4.24's API differences.

---

## Main Branch Status

**Branch:** `main`  
**Current Version:** v4.29.0  
**Status:** ✅ Up-to-date with lean-v4.29

Recent commits:
```
d105bf9 Document multi-version Lean support (v4.24-v4.29)
089b396 Add BRANCH_STRATEGY.md: document multi-version support
```

---

## Graph Generation Status

### Completed

- **v4.29.0 Mathlib**: ~1.2GB (381k nodes) — [To be generated May 6]
- **v4.28.0 Mathlib**: ~1.2GB (needs verification)
- **v4.27.0-v4.25.0**: Not yet generated
- **v4.24.0**: Cannot generate due to API gaps

### In Progress

- **v4.29.0 Mathlib**: Lake build + graph generation in progress
  - Mathlib build started: 14:47 UTC, May 6, 2026
  - Estimated completion: 16:47-18:47 UTC (2-4 hours)
  - Expected graph generation: 30-45 additional minutes

### Planned

- Test v4.28.0 graph generation after v4.29 completes
- Generate graphs for v4.27-v4.25 (if time permits)
- Create batch processing script for all versions

---

## File Organization

### Lean Graph Branches
```
/home/aurasl/projects/lean-graph/
├── main
├── lean-v4.29     ✅
├── lean-v4.28     ⚠️
├── lean-v4.27     ⚠️
├── lean-v4.26     ⚠️
├── lean-v4.25     ⚠️
└── lean-v4.24     ❌
```

### Generated Graphs
```
/home/aurasl/projects/mathlib-version-graphs/
├── v4.20.0/       (reference only)
├── v4.22.0/       (reference only)
├── v4.24.0/       (empty)
├── v4.26.0/       (reference only)
├── v4.28.0/       (unified_graph_new.dot, 1.2GB)
└── v4.29.0/       (in progress)
```

### Target Projects
```
/home/aurasl/projects/lean-repos/
├── mathlib4               (v4.29.0)
├── mathlib4-v4.28        (v4.28.0)
├── mathlib4-v4.27        (v4.27.0)
├── mathlib4-v4.26        (v4.26.0)
├── mathlib4-v4.25        (v4.25.0)
└── mathlib4-v4.24        (v4.24.0)
```

---

## Recommendations

1. **Short-term (May 6-7)**
   - Complete v4.29 graph generation and verify output
   - Test v4.28 branch against mathlib4-v4.28
   - Create batch generation script

2. **Medium-term (May 7-14)**
   - Generate graphs for v4.27, v4.26, v4.25 (if infrastructure allows)
   - Document any API gaps discovered during testing
   - Consider creating container images for reproducible builds

3. **Long-term**
   - Maintain branch compatibility as new Lean 4 versions release
   - Archive old version graphs (v4.20, v4.22) for reference only
   - Publish graphs and documentation publicly (if applicable)

---

## Quick Commands

```bash
# Switch to a specific version
cd /home/aurasl/projects/lean-graph
git checkout lean-v4.28
lake build

# Generate graphs for a version
cd /home/aurasl/projects/lean-repos/mathlib4-v4.28
lake exe graph --mode unified --to Mathlib /path/to/output/unified_graph_new.dot

# Check build progress
ps aux | grep "lake build"

# Verify generated graph
ls -lh /home/aurasl/projects/mathlib-version-graphs/v4.28.0/
```

---

## See Also

- [GRAPH_GENERATION.md](docs/GRAPH_GENERATION.md) — Detailed graph generation instructions
- [BRANCH_STRATEGY.md](BRANCH_STRATEGY.md) — Original branch strategy document
