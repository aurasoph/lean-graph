/-
Copyright (c) 2026 Evan Wang. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Evan Wang
-/


/-!
# Meta (Deprecated)

This module is deprecated. Use `import ImportGraph.Tools` instead.
-/

public meta import ImportGraph.Tools
import Lean

open Lean

-- deprecated 2026-02-01
#eval do
  logWarning "`ImportGraph.Imports` is deprecated! use `import ImportGraph.Tools` instead."
