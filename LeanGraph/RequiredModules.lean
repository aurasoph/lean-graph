/-
Copyright (c) 2026 Evan Wang. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Evan Wang
-/

module

/-!
# RequiredModules (Deprecated)

This module is deprecated. Use `import LeanGraph.Imports.RequiredModules` instead.
-/

public import LeanGraph.Imports.RequiredModules
import Lean

open Lean

-- deprecated 2026-02-01
#eval do
  logWarning "`LeanGraph.RequiredModules` is deprecated! use `import LeanGraph.Imports.RequiredModules` instead."
