/-
Copyright (c) 2026 Evan Wang. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Evan Wang
-/

module

public import ImportGraph.Types
public import ImportGraph.Export.DotFile
public import ImportGraph.Export.Gexf
public import ImportGraph.Graph.Filter
public import ImportGraph.Graph.ProofDeps
public import ImportGraph.Graph.Structures
public import ImportGraph.Graph.TransitiveClosure
public import ImportGraph.Graph.TypeDeps
public import ImportGraph.Graph.Unified
public import ImportGraph.Imports.FromSource
public import ImportGraph.Imports.ImportGraph
public import ImportGraph.Imports.Redundant
public import ImportGraph.Imports.RequiredModules
public import ImportGraph.Imports.Unused
public import ImportGraph.Lean.Environment
public import ImportGraph.Lean.Name
public import ImportGraph.Lean.WithImportModules
public meta import ImportGraph.Tools
public meta import ImportGraph.Tools.FindHome
public meta import ImportGraph.Tools.ImportDiff
public meta import ImportGraph.Tools.MinImports
public meta import ImportGraph.Tools.RedundantImports
public import ImportGraph.Util.CurrentModule
public import ImportGraph.Util.FindSorry

/-!
# ImportGraph

Tools for analyzing and visualizing Lean 4 code dependency graphs.

Combines multiple dependency types into unified graphs suitable for:
- Machine learning on proof patterns
- Dependency visualization and analysis
- Module-level and declaration-level dependency studies

## Core Modules

- **Types**: Centralized type definitions (EdgeType, DeclarationType, UnifiedGraph)
- **Graph**: Multiple graph analysis modes (unified, structures, types, proofs)
- **Export**: Output formats (DOT, GEXF, CSV, JSONL)
- **Imports**: Import dependency analysis
- **Tools**: CLI utilities and metadata extraction
-/
