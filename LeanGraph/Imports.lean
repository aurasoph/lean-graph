/-
Copyright (c) 2026 Evan Wang. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Evan Wang
-/

module

/-!
# Imports (Deprecated)

This module is deprecated. Use `import LeanGraph` and select specific submodules instead.
-/

public import LeanGraph.Export.DotFile
public import LeanGraph.Export.Gexf
public import LeanGraph.Graph.Filter
public import LeanGraph.Graph.TransitiveClosure
public import LeanGraph.Imports.FromSource
public import LeanGraph.Imports.LeanGraph
public import LeanGraph.Imports.Redundant
public import LeanGraph.Imports.RequiredModules
public import LeanGraph.Imports.Unused
public import LeanGraph.Lean.Environment
public import LeanGraph.Lean.Name
public import LeanGraph.Lean.WithImportModules
public import LeanGraph.Util.FindSorry
public meta import LeanGraph.Export.DotFile
public meta import LeanGraph.Export.Gexf
public meta import LeanGraph.Graph.Filter
public meta import LeanGraph.Graph.TransitiveClosure
public meta import LeanGraph.Imports.FromSource
public meta import LeanGraph.Imports.LeanGraph
public meta import LeanGraph.Imports.Redundant
public meta import LeanGraph.Imports.RequiredModules
public meta import LeanGraph.Imports.Unused
public meta import LeanGraph.Lean.Environment
public meta import LeanGraph.Lean.Name
public meta import LeanGraph.Lean.WithImportModules
public meta import LeanGraph.Util.FindSorry

import Lean

open Lean

-- deprecated 2026-02-01
#eval do
  logWarning "`LeanGraph.Imports` is deprecated! use a subset of`import LeanGraph` instead."
