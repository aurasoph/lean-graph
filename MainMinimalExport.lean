/-
Copyright (c) 2026 Evan Wang. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Evan Wang
-/
import LeanGraph.Export.MinimalLibrary
import LeanGraph.Lean.WithImportModules
import Lean

/-!
# `lake exe minimal_export`

Emit a self-contained Lean file containing exactly the declarations a target
needs from a set of modules, in dependency order, with none of those modules
imported.

```
lake exe minimal_export --target Point.shift_origin_x --modules TestTarget \
  --src-root . --out min_export.lean
```

`--modules` and `--src-root` are comma-separated. Everything outside the given
modules is assumed provided by the prelude / a base import.
-/

open Lean LeanGraph.MinimalLibrary

/-- Parse `--flag value` pairs into an association list. -/
partial def parseFlags : List String → List (String × String)
  | flag :: val :: rest =>
    if flag.startsWith "--" then ((flag.drop 2).toString, val) :: parseFlags rest
    else parseFlags (val :: rest)
  | _ => []

def flag? (opts : List (String × String)) (k : String) : Option String :=
  (opts.find? (·.1 == k)).map (·.2)

def splitCsv (s : String) : List String :=
  (s.splitOn ",").filter (· != "")

def main (args : List String) : IO Unit := do
  let opts := parseFlags args
  let some targetStr := flag? opts "target"
    | throw <| IO.userError "missing --target"
  let some modulesStr := flag? opts "modules"
    | throw <| IO.userError "missing --modules"
  let target := targetStr.toName
  let modules := (splitCsv modulesStr).map (·.toName) |>.toArray
  let srcRoots : SearchPath :=
    (splitCsv ((flag? opts "src-root").getD ".")).map (fun s => (⟨s⟩ : System.FilePath))
  initSearchPath (← findSysroot)
  let text ← Core.withImportModules modules do
    let env ← getEnv
    (minimalExport env target modules srcRoots : IO String)
  match flag? opts "out" with
  | some f => IO.FS.writeFile f text; IO.eprintln s!"wrote {f}"
  | none => IO.print text
