/-
Copyright (c) 2026 Evan Wang. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Evan Wang
-/


/-!
# RequiredModules (Deprecated)

This module is deprecated. Use `import ImportGraph.Imports.RequiredModules` instead.
-/

import ImportGraph.Imports.RequiredModules
import Lean

open Lean

-- deprecated 2026-02-01
#eval do
  logWarning "`ImportGraph.RequiredModules` is deprecated! use `import ImportGraph.Imports.RequiredModules` instead."
