#!/usr/bin/env python3
"""
Convert unified_graph.dot + unified_graph_nodes.csv → unified.db

Usage:
    python3 docs/convert_unified.py unified_graph.dot unified_graph_nodes.csv docs/data/unified.db

Schema produced:
    nodes(name TEXT PRIMARY KEY, decl_type TEXT, module TEXT)
    edges(src TEXT NOT NULL, dst TEXT NOT NULL, kind TEXT NOT NULL)

Edge kind mapping (DOT attribute → DB):
    sig     → signature
    extends → extends
    field   → field
    proof   → proof
    def     → def
    docref  → docref
"""

import re
import sqlite3
import sys
import time
from pathlib import Path

# DOT → DB kind normalization
KIND_MAP = {
    "sig":     "signature",
    "extends": "extends",
    "field":   "field",
    "proof":   "proof",
    "def":     "def",
    "docref":  "docref",
}

# Regex to extract kind= from an edge attribute list.
# Handles both quoted and unquoted values: kind=foo or kind="foo"
_KIND_RE = re.compile(r'\bkind="?([^",\]\s]+)"?')


def create_db(db_path: Path) -> sqlite3.Connection:
    db_path.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(str(db_path))
    conn.executescript("""
        CREATE TABLE IF NOT EXISTS nodes (
            name      TEXT PRIMARY KEY,
            decl_type TEXT NOT NULL DEFAULT '',
            module    TEXT NOT NULL DEFAULT ''
        );
        CREATE TABLE IF NOT EXISTS edges (
            src  TEXT NOT NULL,
            dst  TEXT NOT NULL,
            kind TEXT NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_src  ON edges(src);
        CREATE INDEX IF NOT EXISTS idx_dst  ON edges(dst);
        CREATE INDEX IF NOT EXISTS idx_kind ON edges(kind);
    """)
    conn.commit()
    return conn


def load_nodes_csv(conn: sqlite3.Connection, csv_path: Path) -> int:
    """Insert rows from the nodes CSV. Expected format: name,decl_type,module (with quotes)."""
    _FIELD_RE = re.compile(r'"([^"]*)"')
    count = 0
    with open(csv_path, encoding="utf-8") as f:
        header = f.readline()  # skip header
        for line in f:
            line = line.rstrip("\n")
            if not line:
                continue
            fields = _FIELD_RE.findall(line)
            if len(fields) < 3:
                continue
            name, decl_type, module = fields[0], fields[1], fields[2]
            conn.execute(
                "INSERT OR REPLACE INTO nodes(name, decl_type, module) VALUES (?, ?, ?)",
                (name, decl_type, module),
            )
            count += 1
            if count % 100_000 == 0:
                print(f"  {count:,} nodes loaded...", flush=True)
    conn.commit()
    return count


def load_dot_edges(conn: sqlite3.Connection, dot_path: Path) -> int:
    """Parse DOT edge lines and insert into edges table."""
    # Edge lines: "A" -> "B" [... kind=foo ...];
    _EDGE_RE = re.compile(r'^\s*"([^"]+)"\s*->\s*"([^"]+)"\s*\[([^\]]*)\]')

    batch: list[tuple[str, str, str]] = []
    BATCH_SIZE = 50_000
    count = 0
    skipped = 0

    with open(dot_path, encoding="utf-8") as f:
        for line in f:
            m = _EDGE_RE.match(line)
            if not m:
                continue
            src, dst, attrs = m.group(1), m.group(2), m.group(3)
            km = _KIND_RE.search(attrs)
            if not km:
                skipped += 1
                continue
            raw_kind = km.group(1)
            kind = KIND_MAP.get(raw_kind, raw_kind)
            batch.append((src, dst, kind))
            count += 1

            if len(batch) >= BATCH_SIZE:
                conn.executemany(
                    "INSERT INTO edges(src, dst, kind) VALUES (?, ?, ?)", batch
                )
                conn.commit()
                batch.clear()
                print(f"  {count:,} edges inserted...", flush=True)

    if batch:
        conn.executemany(
            "INSERT INTO edges(src, dst, kind) VALUES (?, ?, ?)", batch
        )
        conn.commit()

    if skipped:
        print(f"  Warning: {skipped} edge lines had no kind= attribute (skipped).")
    return count


def print_stats(conn: sqlite3.Connection) -> None:
    node_count = conn.execute("SELECT COUNT(*) FROM nodes").fetchone()[0]
    edge_count = conn.execute("SELECT COUNT(*) FROM edges").fetchone()[0]
    print(f"  {node_count:,} nodes")
    print(f"  {edge_count:,} edges total")
    for kind, cnt in conn.execute(
        "SELECT kind, COUNT(*) FROM edges GROUP BY kind ORDER BY COUNT(*) DESC"
    ):
        print(f"    {kind:<12} {cnt:>10,}")


def main() -> None:
    if len(sys.argv) != 4:
        print("Usage: convert_unified.py <dot_file> <nodes_csv> <output.db>")
        sys.exit(1)

    dot_path   = Path(sys.argv[1])
    csv_path   = Path(sys.argv[2])
    db_path    = Path(sys.argv[3])

    for p in (dot_path, csv_path):
        if not p.exists():
            print(f"Error: {p} not found")
            sys.exit(1)

    if db_path.exists():
        print(f"Removing existing {db_path}")
        db_path.unlink()

    t0 = time.time()
    conn = create_db(db_path)

    print(f"Loading nodes from {csv_path}...")
    n_nodes = load_nodes_csv(conn, csv_path)
    print(f"  {n_nodes:,} nodes loaded in {time.time()-t0:.1f}s")

    print(f"Loading edges from {dot_path}...")
    t1 = time.time()
    n_edges = load_dot_edges(conn, dot_path)
    print(f"  {n_edges:,} edges loaded in {time.time()-t1:.1f}s")

    print(f"\nDatabase stats:")
    print_stats(conn)

    db_mb = db_path.stat().st_size / 1_048_576
    print(f"\nOutput: {db_path} ({db_mb:.1f} MB)")
    print(f"Total time: {time.time()-t0:.1f}s")

    conn.close()


if __name__ == "__main__":
    main()
