#!/usr/bin/env python3
"""
Convert DOT graph files to JSON format for web explorer.
Handles massive graphs by parsing line-by-line.
"""

import json
import re
import sys
from pathlib import Path

def parse_dot_to_json(dot_file):
    """Parse DOT file into JSON graph structure."""
    nodes = {}
    edges = []
    
    # Regular expressions
    node_pattern = re.compile(r'^\s*"([^"]+)"\s*\[([^\]]*)\];?')
    edge_pattern = re.compile(r'^\s*"([^"]+)"\s*->\s*"([^"]+)";?')
    
    print(f"Parsing {dot_file}...")
    line_count = 0
    
    with open(dot_file, 'r') as f:
        for line in f:
            line_count += 1
            if line_count % 100000 == 0:
                print(f"  Processed {line_count:,} lines, {len(nodes):,} nodes, {len(edges):,} edges")
            
            # Match node declarations
            node_match = node_pattern.match(line)
            if node_match:
                node_id = node_match.group(1)
                if node_id not in nodes:
                    nodes[node_id] = {
                        "id": node_id,
                        "label": node_id.split('.')[-1],  # Use last component as label
                        "fullName": node_id
                    }
                continue
            
            # Match edges
            edge_match = edge_pattern.match(line)
            if edge_match:
                source = edge_match.group(1)
                target = edge_match.group(2)
                
                # Add nodes if not already present
                if source not in nodes:
                    nodes[source] = {
                        "id": source,
                        "label": source.split('.')[-1],
                        "fullName": source
                    }
                if target not in nodes:
                    nodes[target] = {
                        "id": target,
                        "label": target.split('.')[-1],
                        "fullName": target
                    }
                
                edges.append({"source": source, "target": target})
    
    print(f"✓ Parsed {line_count:,} lines: {len(nodes):,} nodes, {len(edges):,} edges")
    
    return {
        "nodes": list(nodes.values()),
        "edges": edges
    }

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
    
    for graph_name, dot_file in graphs.items():
        dot_path = Path(dot_file)
        if not dot_path.exists():
            print(f"⚠ Skipping {graph_name}: {dot_file} not found")
            continue
        
        # Convert to JSON
        graph_data = parse_dot_to_json(dot_path)
        
        # Write JSON
        output_file = output_dir / f"{graph_name}.json"
        print(f"Writing {output_file}...")
        with open(output_file, 'w') as f:
            json.dump(graph_data, f, separators=(',', ':'))
        
        size_mb = output_file.stat().st_size / (1024 * 1024)
        print(f"✓ Created {output_file} ({size_mb:.1f} MB)\n")
    
    print("All graphs converted successfully!")
    print("Note: type-deps and proof-deps are large files (165MB and 665MB).")
    print("For GitHub Pages deployment, only structures and imports are included.")

if __name__ == "__main__":
    main()
