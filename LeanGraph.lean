/-
Copyright (c) 2026 Evan Wang. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Evan Wang
-/

module

public import LeanGraph.Types
public import LeanGraph.Export.DotFile
public import LeanGraph.Export.Gexf
public import LeanGraph.Export.ModuleAggregation
public import LeanGraph.Export.NamespaceAggregation
public import LeanGraph.Graph.Filter
public import LeanGraph.Graph.ProofDeps
public import LeanGraph.Graph.Structures
public import LeanGraph.Graph.TransitiveClosure
public import LeanGraph.Graph.TypeDeps
public import LeanGraph.Graph.Unified
public import LeanGraph.Imports.FromSource
public import LeanGraph.Imports.LeanGraph
public import LeanGraph.Imports.Redundant
public import LeanGraph.Imports.RequiredModules
public import LeanGraph.Imports.Unused
public import LeanGraph.Lean.Environment
public import LeanGraph.Lean.Name
public import LeanGraph.Lean.WithImportModules
public meta import LeanGraph.Tools
public meta import LeanGraph.Tools.FindHome
public meta import LeanGraph.Tools.ImportDiff
public meta import LeanGraph.Tools.MinImports
public meta import LeanGraph.Tools.RedundantImports
public import LeanGraph.Util.CurrentModule
public import LeanGraph.Util.FindSorry

/-!
# LeanGraph

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
