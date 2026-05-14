# Generating Unified Graphs for Multi-Version Lean Support

This guide explains how to generate unified import graphs for Lean projects across different Lean 4 versions (v4.24 through v4.29).

## Prerequisites

- Multiple version-specific branches of lean-graph: `lean-v4.24` through `lean-v4.29`
- Target Lean projects (e.g., mathlib4) built for the target version
- At least 2GB free disk space per graph (v4.29 Mathlib is ~1.2GB)

## Quick Start: Generating v4.29 Graphs

The recommended and fully-tested workflow is for Lean v4.29:

```bash
# 1. Ensure the lean-graph lean-v4.29 branch is up-to-date
cd /home/aurasl/projects/lean-graph
git checkout lean-v4.29
lake build

# 2. Run from the target project directory (must have importGraph dependency)
cd /home/aurasl/projects/lean-repos/mathlib4
lake exe graph --mode unified --to Mathlib /path/to/output/unified_graph_new.dot

# 3. Optional: Generate module-level aggregation
lake exe graph --mode unified --aggregate module /path/to/output/unified_graph_new_nodes.csv --to Mathlib /path/to/output/unified_graph_new.dot
```

**Expected timing:** ~45 minutes for Mathlib (381k nodes, 1.3GB output)

## Multi-Version Workflow

For supporting multiple Lean versions, use version-specific branches:

### Step 1: Switch to the target version branch

```bash
cd /home/aurasl/projects/lean-graph
git checkout lean-v4.28  # or lean-v4.27, lean-v4.26, etc.
lake build
```

### Step 2: Build the target project for that version

Ensure your target project (mathlib4, batteries, aesop, etc.) is compiled for the target Lean version:

```bash
cd /path/to/target/project
cat lean-toolchain  # Should match the version you're generating for
lake build
```

### Step 3: Generate the unified graph

From the target project directory:

```bash
lake exe graph --mode unified --to TargetModule /output/path/unified_graph_new.dot
```

For Mathlib specifically:
```bash
lake exe graph --mode unified --to Mathlib /output/path/unified_graph_new.dot
```

### Step 4: Optional - Generate module aggregation

To create a CSV file of module-level dependencies:

```bash
lake exe graph --mode unified --aggregate module /output/path/unified_graph_new_nodes.csv --to Mathlib /output/path/unified_graph_new.dot
```

## Version-Specific Configuration

Each branch has a specific Lean version pinned:

| Branch | Lean Version | Status | Notes |
|--------|-------------|--------|-------|
| `lean-v4.29` | v4.29.0 | ✅ Fully tested | Recommended, all features work |
| `lean-v4.28` | v4.28.0 | ⚠️ Untested | API changes ported but needs validation |
| `lean-v4.27` | v4.27.0 | ⚠️ Untested | Requires verification |
| `lean-v4.26` | v4.26.0 | ⚠️ Untested | Requires verification |
| `lean-v4.25` | v4.25.0 | ⚠️ Untested | Requires verification |
| `lean-v4.24` | v4.24.0 | ❌ Incomplete | API gaps, not fully compatible |

## Understanding the Output

### unified_graph_new.dot

A Graphviz DOT file with all edges color-coded by type:

```dot
digraph {
  "Mathlib.Data.Set" -> "Mathlib.Data.Fintype" [label="extends", color="red"];
  "Mathlib.Data.List" -> "Mathlib.Data.Set" [label="proof", color="blue"];
  ...
}
```

Edge colors:
- **Red**: Structure inheritance (`extends`)
- **Green**: Definition invocations (`def`)
- **Blue**: Proof invocations (`proof`)
- **Purple**: Type signatures (`sig`)
- **Orange**: Field composition (`field`)
- **Gray**: Docstring references (`docref`)

**Size expectations:**
- Mathlib v4.29: ~1.2GB (381k nodes, ~8M edges)
- Mathlib v4.28: ~1.2GB (similar scale)

### unified_graph_new_nodes.csv

Optional CSV output from `--aggregate module`:

```csv
module,imports,importedBy,proofDeps,typeDeps,extends,field
Mathlib.Data.Set,15,42,1203,87,12,3
Mathlib.Data.List,8,31,891,65,8,2
...
```

## Troubleshooting

### Lake complains about importGraph dependency

**Error:** `missing package 'ImportGraph'`

**Solution:** Ensure the target project has importGraph declared in its lakefile:

```lean
require importGraph from "/path/to/lean-graph"
```

And run `lake update` to refresh dependencies.

### Out of memory

**Error:** `std::bad_alloc` or similar during graph generation

**Solution:** The unified graph construction can use 4-8GB RAM for large projects. Ensure sufficient system memory or consider filtering:

```bash
# Generate only proof dependencies
lake exe graph --mode unified --edge-types proof --to Mathlib output.dot

# Generate with --include-direct to reduce scope
lake exe graph --mode unified --include-direct --to Mathlib output.dot
```

### Build fails with API incompatibility

**Error:** `unknown declaration 'Lean.xxx'` or similar

**Solution:** Verify the Lean version in lean-toolchain matches the branch you're on:

```bash
cd /path/to/target/project
cat lean-toolchain
cd /home/aurasl/projects/lean-graph
git status  # Check current branch
```

If versions mismatch, rebuild the target project for the correct Lean version.

### Graph generation never completes

Graph generation for Mathlib typically takes 40-60 minutes. Monitor progress with:

```bash
# Watch file size growth
watch -n 5 'ls -lh /output/path/unified_graph_new.dot'

# Monitor CPU/memory
top -p $(pgrep -f "lake exe graph")
```

## Advanced: Customizing Output

### Filter by edge types

Generate only specific edge types:

```bash
# Only proof and signature dependencies
lake exe graph --mode unified --edge-types proof,sig --to Mathlib output.dot

# Only structural edges
lake exe graph --mode unified --edge-types extends,field --to Mathlib output.dot
```

### Include or exclude auxiliary code

By default, the graph includes only "human-written" declarations (filtered via doc-gen4 rules).

```bash
# Include compiler-generated declarations (~7x more nodes)
lake exe graph --mode unified --include-aux --to Mathlib output.dot

# Include Lean standard library
lake exe graph --mode unified --include-lean --to Mathlib output.dot
```

## Batch Processing Multiple Versions

To generate graphs for all supported versions:

```bash
#!/bin/bash
set -e

VERSIONS=("v4.29" "v4.28" "v4.27" "v4.26" "v4.25")
OUTPUT_DIR="/home/aurasl/projects/mathlib-version-graphs"

for version in "${VERSIONS[@]}"; do
    echo "=== Generating $version graphs ==="
    
    cd /home/aurasl/projects/lean-graph
    git checkout lean-${version}
    lake build
    
    cd /home/aurasl/projects/lean-repos/mathlib4-${version}
    mkdir -p "$OUTPUT_DIR/${version}.0"
    
    lake exe graph \
        --mode unified \
        --to Mathlib \
        "$OUTPUT_DIR/${version}.0/unified_graph_new.dot"
    
    echo "✓ $version complete"
done

echo "All graphs generated successfully"
```

## Performance Notes

- **Graph construction**: O(E) where E is number of edges (~8M for Mathlib)
- **File I/O**: Streaming DOT output avoids memory overhead
- **Typical bottleneck**: Lean environment loading (~15 min) + proof body traversal (~30 min)

## Quality Assurance

After generating a new graph, verify:

1. **File size is reasonable** — v4.29 Mathlib should be ~1.2GB
2. **No truncation** — Verify the DOT file ends with a closing brace: `}`
3. **Spot checks** — Look for expected declarations:
   ```bash
   grep "Mathlib.Data.Set" /output/path/unified_graph_new.dot
   ```

## See Also

- [FILTERING.md](FILTERING.md) — Detailed explanation of filtering rules
- [README.md](README.md) — Graph interpretation and edge types
- [IMPLEMENTATION.md](IMPLEMENTATION.md) — Technical details of graph construction
