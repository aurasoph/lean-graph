# Mathlib Dependency Explorer

Interactive web interface for exploring dependency relationships in Mathlib4.

## Available Graphs

### 🏗️ Structures (1,618 nodes)
Typeclass and structure inheritance hierarchy. Explore how mathematical structures build upon each other:
- `Group → Ring → Field`
- `Topological space → Metric space → Normed space`
- `Category → Functor → Monad`

### 📦 Imports (10,284 modules)  
Module import relationships across Lean, Std, and Mathlib:
- See which files depend on core modules like `Data.List.Basic`
- Trace import paths between different areas of mathematics
- Understand the modular structure of Mathlib

## Usage Instructions

### Two Interaction Modes

**🔍 Search Mode** (default):
- Type in the search box to find specific nodes
- Click nodes to expand their neighborhoods  
- Build custom views by exploring multiple areas

**🎯 Traversal Mode**:
- Click any node to make it "active"
- See only immediate neighbors (1 edge away)
- Navigate step-by-step through dependencies

### Controls
- **+ Parents**: Show what the active node depends on
- **+ Children**: Show what depends on the active node  
- **Center**: Reset the view
- **Clear All**: Start fresh

## Missing: Large Graphs

**Type Dependencies** (293K nodes, 165MB) and **Proof Dependencies** (321K nodes, 665MB) are too large for GitHub Pages.

### 🏠 Local Setup for Full Experience

```bash
git clone https://github.com/aurasoph/lean-graph.git
cd lean-graph/web-explorer
python3 convert_to_json.py
python3 -m http.server 8000
open http://localhost:8000
```

---

**About**: These graphs represent the complete Lean + Std + Mathlib proof environment with auto-generated declarations filtered out to show only human-written mathematics.

**Source**: Generated from [Mathlib4](https://github.com/leanprover-community/mathlib4) using the [import-graph](https://github.com/leanprover-community/import-graph) tool.