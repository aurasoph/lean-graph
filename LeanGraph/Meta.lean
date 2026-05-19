/-
Copyright (c) 2026 Evan Wang. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Evan Wang
-/

module

/-!
# Meta (Deprecated)

This module is deprecated. Use `import LeanGraph.Tools` instead.
-/

public meta import LeanGraph.Tools
import Lean

open Lean

-- deprecated 2026-02-01
#eval do
  logWarning "`LeanGraph.Imports` is deprecated! use `import LeanGraph.Tools` instead."
