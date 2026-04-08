#!/usr/bin/env python3
"""
Convert DOT graph files to SQLite databases for efficient web querying.
Much more efficient than JSON for large graphs.
"""

import sqlite3
import re
import sys
from pathlib import Path

def create_graph_db(dot_file, db_file):
    """Convert DOT file to SQLite database with optimized schema."""
    
    # Create database
    conn = sqlite3.connect(db_file)
    cursor = conn.cursor()
    
    # Create tables with indexes for fast queries
    cursor.execute('''
        CREATE TABLE nodes (
            id TEXT PRIMARY KEY,
            label TEXT,
            full_name TEXT
        )
    ''')
    
    cursor.execute('''
        CREATE TABLE edges (
            source TEXT,
            target TEXT,
            PRIMARY KEY (source, target),
            FOREIGN KEY (source) REFERENCES nodes(id),
            FOREIGN KEY (target) REFERENCES nodes(id)
        )
    ''')
    
    # Create indexes for fast neighborhood queries
    cursor.execute('CREATE INDEX idx_edges_source ON edges(source)')
    cursor.execute('CREATE INDEX idx_edges_target ON edges(target)')
    cursor.execute('CREATE INDEX idx_nodes_label ON nodes(label)')
    
    # Regular expressions for parsing
    node_pattern = re.compile(r'^\s*"([^"]+)"\s*\[([^\]]*)\];?')
    edge_pattern = re.compile(r'^\s*"([^"]+)"\s*->\s*"([^"]+)";?')
    
    nodes_seen = set()
    node_count = 0
    edge_count = 0
    line_count = 0
    
    print(f"Converting {dot_file} to {db_file}...")
    
    # Parse DOT file line by line
    with open(dot_file, 'r') as f:
        for line in f:
            line_count += 1
            if line_count % 100000 == 0:
                print(f"  Processed {line_count:,} lines, {node_count:,} nodes, {edge_count:,} edges")
            
            # Match node declarations
            node_match = node_pattern.match(line)
            if node_match:
                node_id = node_match.group(1)
                if node_id not in nodes_seen:
                    label = node_id.split('.')[-1]  # Use last component as label
                    cursor.execute(
                        'INSERT INTO nodes (id, label, full_name) VALUES (?, ?, ?)',
                        (node_id, label, node_id)
                    )
                    nodes_seen.add(node_id)
                    node_count += 1
                continue
            
            # Match edges
            edge_match = edge_pattern.match(line)
            if edge_match:
                source = edge_match.group(1)
                target = edge_match.group(2)
                
                # Add nodes if not seen
                for node_id in [source, target]:
                    if node_id not in nodes_seen:
                        label = node_id.split('.')[-1]
                        cursor.execute(
                            'INSERT INTO nodes (id, label, full_name) VALUES (?, ?, ?)',
                            (node_id, label, node_id)
                        )
                        nodes_seen.add(node_id)
                        node_count += 1
                
                # Add edge (handle duplicates)
                cursor.execute(
                    'INSERT OR IGNORE INTO edges (source, target) VALUES (?, ?)',
                    (source, target)
                )
                edge_count += 1
    
    # Commit and create additional useful views
    cursor.execute('''
        CREATE VIEW node_stats AS
        SELECT 
            n.id,
            n.label,
            n.full_name,
            COALESCE(parents.count, 0) as parent_count,
            COALESCE(children.count, 0) as child_count
        FROM nodes n
        LEFT JOIN (
            SELECT target as id, COUNT(*) as count 
            FROM edges GROUP BY target
        ) parents ON n.id = parents.id
        LEFT JOIN (
            SELECT source as id, COUNT(*) as count 
            FROM edges GROUP BY source  
        ) children ON n.id = children.id
    ''')
    
    conn.commit()
    
    # Get database size
    db_size = Path(db_file).stat().st_size / (1024 * 1024)
    
    print(f"✓ Created {db_file} ({db_size:.1f} MB)")
    print(f"  {node_count:,} nodes, {edge_count:,} edges")
    
    # Test query performance
    start_time = __import__('time').time()
    cursor.execute("SELECT COUNT(*) FROM nodes WHERE label LIKE 'Ring%'")
    result = cursor.fetchone()[0]
    query_time = (__import__('time').time() - start_time) * 1000
    print(f"  Query test: {result} Ring* nodes found in {query_time:.1f}ms\n")
    
    conn.close()
    return node_count, edge_count, db_size

def main():
    # Define graphs to convert
    graphs = {
        "structures": "../mathlib_graphs/mathlib_structures.dot",
        "imports": "../mathlib_graphs/mathlib_imports.dot",
        "type-deps": "../mathlib_graphs/mathlib_type_deps.dot", 
        "proof-deps": "../mathlib_graphs/mathlib_proof_deps.dot",
    }
    
    output_dir = Path("data")
    output_dir.mkdir(exist_ok=True)
    
    total_size = 0
    
    for graph_name, dot_file in graphs.items():
        dot_path = Path(dot_file)
        if not dot_path.exists():
            print(f"⚠ Skipping {graph_name}: {dot_file} not found")
            continue
        
        # Convert to SQLite
        db_file = output_dir / f"{graph_name}.db"
        try:
            node_count, edge_count, db_size = create_graph_db(dot_path, db_file)
            total_size += db_size
        except Exception as e:
            print(f"❌ Error converting {graph_name}: {e}\n")
            continue
    
    print(f"✅ Conversion complete! Total size: {total_size:.1f} MB")
    print("\nDatabase files are much more efficient than JSON:")
    print("- Smaller file sizes due to normalization and compression")
    print("- Fast neighborhood queries without loading entire graph")
    print("- Support for complex filtering and search")

if __name__ == "__main__":
    main()