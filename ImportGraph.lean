/-
Copyright (c) 2026 Evan Wang. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Evan Wang
-/


import ImportGraph.Types
import ImportGraph.Export.DotFile
import ImportGraph.Export.Gexf
import ImportGraph.Graph.Filter
import ImportGraph.Graph.ProofDeps
import ImportGraph.Graph.Structures
import ImportGraph.Graph.TransitiveClosure
import ImportGraph.Graph.TypeDeps
import ImportGraph.Graph.Unified
import ImportGraph.Imports.FromSource
import ImportGraph.Imports.ImportGraph
import ImportGraph.Imports.Redundant
import ImportGraph.Imports.RequiredModules
import ImportGraph.Imports.Unused
import ImportGraph.Lean.Environment
import ImportGraph.Lean.Name
import ImportGraph.Lean.WithImportModules
public meta import ImportGraph.Tools
public meta import ImportGraph.Tools.FindHome
public meta import ImportGraph.Tools.ImportDiff
public meta import ImportGraph.Tools.MinImports
public meta import ImportGraph.Tools.RedundantImports
import ImportGraph.Util.CurrentModule
import ImportGraph.Util.FindSorry

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
