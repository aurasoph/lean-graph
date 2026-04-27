# Mathlib Dependency Web Explorer

Interactive visualization for exploring Mathlib dependency graphs.

## Online Version

Visit **[https://aurasoph.github.io/lean-graph/](https://aurasoph.github.io/lean-graph/)** to explore:

- **Structures Graph**: typeclass/structure inheritance relationships
- **Imports Graph**: module import dependencies

The unified graph (~381K nodes, ~16M edges) is too large for GitHub Pages and requires a local server.

## Local Setup

### Prerequisites

- Python 3.6+
- Git with Git LFS

### Installation

```bash
git lfs install
git clone https://github.com/aurasoph/lean-graph
cd lean-graph
python3 -m http.server 8000 --directory docs/
# Open http://localhost:8000
```

The large database files (`unified.db`, `imports.db`) download via Git LFS on clone.

## Regenerating Databases

See the [project README](../README.md) for full generation instructions.

**Structures and imports** — place DOT files in `mathlib_graphs/`, then:

```bash
python3 docs/convert_to_db.py
```

**Unified** — reads the DOT file and companion nodes CSV:

```bash
python3 docs/convert_unified.py unified_graph.dot unified_graph_nodes.csv docs/data/unified.db
```

## Database Schema

### Unified database (`unified.db`)

```sql
CREATE TABLE nodes (
    name      TEXT PRIMARY KEY,
    decl_type TEXT NOT NULL,
    module    TEXT NOT NULL
);

CREATE TABLE edges (
    src  TEXT NOT NULL,
    dst  TEXT NOT NULL,
    kind TEXT NOT NULL
);
```

Edge direction: `src` is the dependency, `dst` is the dependent (`dst` uses `src`).

### Structures and imports databases

```sql
CREATE TABLE nodes (id TEXT PRIMARY KEY, label TEXT, node_type TEXT);
CREATE TABLE edges (id INTEGER PRIMARY KEY, source TEXT, target TEXT);
```

## Technical Details

- Built with D3.js force-directed layout and sql.js for in-browser SQLite queries
- Supports drag, zoom, and node positioning
- Client-side search with autocomplete
