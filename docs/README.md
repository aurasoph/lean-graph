# Mathlib Dependency Web Explorer

Interactive visualization tool for exploring Mathlib dependency graphs.

## Online Version

Visit **[https://aurasoph.github.io/lean-graph/](https://aurasoph.github.io/lean-graph/)** to explore:

- **Structures Graph**: typeclass/structure inheritance relationships
- **Imports Graph**: module import dependencies

## Local Setup (Full Version)

For the complete experience including the unified graph (~381K nodes, ~16.1M edges):

### Prerequisites

- Python 3.6+
- Git

### Installation

```bash
# 1. Clone the repository
git clone https://github.com/aurasoph/lean-graph.git
cd lean-graph/web-explorer

# Note: Large database files download via Git LFS (may take several minutes)

# 2. Generate SQLite databases (recommended)
python3 convert_to_db.py

# 3. Start local web server
python3 -m http.server 8000

# 4. Open in browser
open http://localhost:8000
```

### Data Files Generated

**SQLite Databases** (recommended for performance):
- `structures.db` (487KB) - Typeclass inheritance
- `imports.db` (8.8MB) - Module dependencies  
- `type-deps.db` (431MB) - Type signature dependencies
- `proof-deps.db` (1.9GB) - Proof body dependencies

**Alternative JSON Format**:
```bash
# Generate JSON files instead
python3 convert_to_json.py
```
- `structures.json` (242KB) 
- `imports.json` (3.7MB)
- `type-deps.json` (165MB) 
- `proof-deps.json` (665MB)

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

- Built with D3.js force-directed layout and sql.js for database queries
- Supports drag, zoom, and node positioning
- Uses SQLite databases for efficient neighborhood expansion queries
- Falls back to JSON format when databases unavailable
- Handles massive graphs through optimized data structures
- Client-side search with fuzzy matching and autocomplete

## Database Schema

Each SQLite database contains:
```sql
CREATE TABLE nodes (id TEXT PRIMARY KEY, label TEXT, node_type TEXT);
CREATE TABLE edges (id INTEGER PRIMARY KEY, source TEXT, target TEXT);
CREATE INDEX idx_edges_source ON edges(source);
CREATE INDEX idx_edges_target ON edges(target);
CREATE VIEW node_stats AS SELECT id, 
    (SELECT COUNT(*) FROM edges WHERE source = nodes.id) as out_degree,
    (SELECT COUNT(*) FROM edges WHERE target = nodes.id) as in_degree
FROM nodes;
```

## Graph Generation

The underlying DOT files are generated using the [import-graph](https://github.com/leanprover-community/import-graph) tool from within Mathlib4:

```bash
# From within mathlib4/ directory:
lake exe graph --mode structures --to Mathlib --include-lean mathlib_structures.dot
lake exe graph --mode imports --to Mathlib --include-lean mathlib_imports.dot  
lake exe graph --mode type-deps --include-lean mathlib_type_deps.dot
lake exe graph --mode proof-deps --include-lean mathlib_proof_deps.dot
```

These graphs represent the complete Lean + Std + Mathlib proof environment (~381K human-written constants) with compiler-generated declarations filtered out. The unified graph combines all dependency types into a single database; see `AGENT_GUIDE.md` for the full schema and query reference.