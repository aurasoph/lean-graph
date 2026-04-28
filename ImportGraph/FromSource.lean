/-
Copyright (c) 2026 Evan Wang. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Evan Wang
-/

module

/-!
# FromSource (Deprecated)

This module is deprecated. Use `ImportGraph.Imports.FromSource` instead.
-/

public import ImportGraph.Imports.FromSource
import Lean

open Lean

-- deprecated 2026-02-01
#eval do
  logWarning "`ImportGraph.FromSource` is deprecated! use `import ImportGraph.Imports.FromSource` instead."
