/-
Copyright (c) 2023 Kim Morrison. All rights reserved.
Modifications (c) 2026 Evan Wang. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Kim Morrison, Paul Lezeau
-/

import Lean.CoreM

open Lean

/-!
# CoreM Environment Loading

Utilities for loading Lean modules into a CoreM environment.

Simplifies the setup of CoreM computation with specific module imports loaded.
-/

def Core.withImportModules (modules : Array Name) {α} (f : CoreM α) : IO α := do
  initSearchPath (← findSysroot)
  unsafe Lean.withImportModules (modules.map (fun m => {module := m})) {} (trustLevel := 1024)
    fun env => Prod.fst <$> Core.CoreM.toIO
        (ctx := { fileName := "<CoreM>", fileMap := default }) (s := { env := env }) do f
