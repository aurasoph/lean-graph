# Mathlib Dependency Web Explorer

Interactive visualization tool for exploring Mathlib dependency graphs.

## Online Version

Visit **[https://aurasoph.github.io/lean-graph/](https://aurasoph.github.io/lean-graph/)** to explore:

- **Structures Graph**: 1,618 typeclass/structure inheritance relationships
- **Imports Graph**: 10,284 module import dependencies

## Local Setup (Full Version)

For the complete experience including large graphs (type-deps: 293K nodes, proof-deps: 321K nodes):

### Prerequisites

- Python 3.6+
- Git

### Installation

```bash
# 1. Clone the repository
git clone https://github.com/aurasoph/lean-graph.git
cd lean-graph/web-explorer

# 2. Generate JSON data files
python3 convert_to_json.py

# 3. Start local web server
python3 -m http.server 8000

# 4. Open in browser
open http://localhost:8000
```

### Data Files Generated

- `structures.json` (242KB) - Typeclass inheritance
- `imports.json` (3.7MB) - Module dependencies  
- `type-deps.json` (165MB) - Type signature dependencies
- `proof-deps.json` (665MB) - Proof body dependencies

## Usage

### Two Interaction Modes

**Search Mode** (default):
- Click nodes to expand their neighborhoods cumulatively
- Search bar to find and add specific nodes
- Build custom subgraphs by exploring multiple areas

**Traversal Mode**:
- Click nodes to set as "active node" 
- View only immediate neighbors (1 edge away) of the active node
- Navigate through the graph one step at a time

### Controls

- **+ Parents/Children**: Expand incoming/outgoing edges from selected node
- **Center**: Reset view to center of graph
- **Clear All**: Remove all nodes from view
- **Search**: Type to find nodes with autocomplete suggestions

### Graph Types

1. **Structures**: Typeclass and structure inheritance hierarchy (e.g., `Group → Ring → Field`)
2. **Imports**: Module import relationships (e.g., which files import `Data.List.Basic`)
3. **Type Deps**: Constants that appear in type signatures (dependencies based on types)
4. **Proof Deps**: Constants used in proof bodies (dependencies based on proofs)

## Technical Details

- Built with D3.js force-directed layout
- Supports drag, zoom, and node positioning
- Parses DOT graph files from the import-graph tool
- Handles massive graphs through efficient JSON format

## Graph Generation

The underlying DOT files are generated using the [import-graph](https://github.com/leanprover-community/import-graph) tool from within Mathlib4:

```bash
# From within mathlib4/ directory:
lake exe graph --mode structures --to Mathlib --include-lean mathlib_structures.dot
lake exe graph --mode imports --to Mathlib --include-lean mathlib_imports.dot  
lake exe graph --mode type-deps --include-lean mathlib_type_deps.dot
lake exe graph --mode proof-deps --include-lean mathlib_proof_deps.dot
```

These graphs represent the complete Lean + Std + Mathlib proof environment (~373K human-written constants) with auto-generated declarations filtered out.