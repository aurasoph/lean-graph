/-
Copyright (c) 2026 Evan Wang. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Evan Wang
-/

module

/-!
# Unused Transitive Imports CLI

Command-line tool for analyzing unused transitive imports.

Usage: `lake exe unused_transitive_imports m1 m2 ...`

For each module, identifies which other modules are transitively imported
but not actually used by any declarations.
-/

public meta import ImportGraph.Lean.WithImportModules
public meta import ImportGraph.Imports.Unused

open Lean

/--
`lake exe unused_transitive_imports m1 m2 ...`

For each specified module `m`, prints those `n` from the argument list which are imported, but transitively unused by `m`.
-/
public meta def main (args : List String) : IO UInt32 := do
  let (flags, args) := args.partition (fun s => s.startsWith "-")
  let mut modules := args.map (fun s => s.toName)
  Core.withImportModules modules.toArray do
    let r ← unusedTransitiveImports modules (verbose := flags.contains "-v" || flags.contains "--verbose")
    for (n, u) in r do
      IO.println s!"{n}: {u}"
    return 0
