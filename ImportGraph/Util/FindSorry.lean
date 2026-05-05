/-
Copyright (c) 2026 Jon Eugster. All rights reserved.
Modifications (c) 2026 Evan Wang. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Jon Eugster
-/

import Lean.Environment
import Lean.Util.Sorry
import ImportGraph.Lean.Environment

namespace ImportGraph

open Lean

/-!
# Sorry Detection

Identifies declarations that contain incomplete proofs (sorry).

Useful for tracking proof obligations and incomplete work in a project.
-/

/--
Array of all constant names which contain a `sorry`.
-/
def allConstantsWithSorry (env : Environment) : NameSet :=
  env.constants.fold (init := ∅) fun acc name info =>
    match info with
    | .thmInfo val => if val.value.hasSorry then acc.insert name else acc
    | .defnInfo val => if val.value.hasSorry then acc.insert name else acc
    | .opaqueInfo val => if val.value.hasSorry then acc.insert name else acc
    | .axiomInfo _ => acc
    | .quotInfo _ => acc
    | .inductInfo  _ => acc
    | .ctorInfo _ => acc
    | .recInfo _ => acc

/--
Array of all module names of modules containing at least one `sorry`.
-/
def allModulesWithSorry (env : Environment) : NameSet :=
  (allConstantsWithSorry env).foldl (init := ∅) fun acc n => match env.getModuleFor? n with
    | some module => acc.insert module
    | none => acc -- TODO: should there be a warning/error if module cannot be found?
