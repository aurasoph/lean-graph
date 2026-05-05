/-
Copyright (c) 2026 Evan Wang. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Evan Wang
-/


/-!
# Imports (Deprecated)

This module is deprecated. Use `import ImportGraph` and select specific submodules instead.
-/

import ImportGraph.Export.DotFile
import ImportGraph.Export.Gexf
import ImportGraph.Graph.Filter
import ImportGraph.Graph.TransitiveClosure
import ImportGraph.Imports.FromSource
import ImportGraph.Imports.ImportGraph
import ImportGraph.Imports.Redundant
import ImportGraph.Imports.RequiredModules
import ImportGraph.Imports.Unused
import ImportGraph.Lean.Environment
import ImportGraph.Lean.Name
import ImportGraph.Lean.WithImportModules
import ImportGraph.Util.FindSorry
public meta import ImportGraph.Export.DotFile
public meta import ImportGraph.Export.Gexf
public meta import ImportGraph.Graph.Filter
public meta import ImportGraph.Graph.TransitiveClosure
public meta import ImportGraph.Imports.FromSource
public meta import ImportGraph.Imports.ImportGraph
public meta import ImportGraph.Imports.Redundant
public meta import ImportGraph.Imports.RequiredModules
public meta import ImportGraph.Imports.Unused
public meta import ImportGraph.Lean.Environment
public meta import ImportGraph.Lean.Name
public meta import ImportGraph.Lean.WithImportModules
public meta import ImportGraph.Util.FindSorry

import Lean

open Lean

-- deprecated 2026-02-01
#eval do
  logWarning "`ImportGraph.Imports` is deprecated! use a subset of`import ImportGraph` instead."
