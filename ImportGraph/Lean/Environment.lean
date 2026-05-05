/-
Copyright (c) 2023 Kim Morrison. All rights reserved.
Modifications (c) 2026 Evan Wang. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Kim Morrison
-/

import Lean.Environment

/-!
# Environment Utilities

Helper functions for querying the Lean environment.

Provides utilities to determine which module a declaration belongs to and
other environment-level queries needed for analysis.
-/

namespace Lean

/-- Return the name of the module in which a declaration was defined. -/
def Environment.getModuleFor? (env : Environment) (declName : Name) : Option Name :=
  match env.getModuleIdxFor? declName with
  | none =>
    if env.constants.map₂.contains declName then
      env.header.mainModule
    else
      none
  | some idx => env.header.moduleNames[idx.toNat]!

end Lean
