/-
Copyright (c) 2023 Kim Morrison. All rights reserved.
Modifications (c) 2026 Evan Wang. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Kim Morrison, Jon Eugster, Evan Wang
-/

import Lean.Data.NameMap.Basic

open Lean

/-!
# DOT Format Export

Utilities for exporting graphs in Graphviz DOT format.

Provides streaming write functionality to handle large graphs (1M+ edges) efficiently
without building the entire output in memory.
-/

/--
Helper which only returns `true` if the `module` is provided and the name `n` lies
inside it.
 -/
private def isInModule (module : Option Name) (n : Name) := match module with
  | some m => m.isPrefixOf n
  | none => false

/--
<<<<<<< HEAD
=======
Write an import graph directly to a file handle in ".dot" format.
This streaming version avoids building the entire string in memory,
which is important for large graphs (1M+ edges).
-/
def writeDotGraph
    (handle : IO.FS.Handle)
    (graph : NameMap (Array Name))
    (_unused : NameSet := ∅)
    (header := "import_graph")
    (_markedPackage : Option Name := none)
    (_withSorry : NameSet := ∅)
    (_directDeps : NameSet := ∅)
    (_from_ _to : NameSet := ∅) : IO Unit := do
  let opening := s!"digraph \"{header}\" " ++ "{"
  handle.putStrLn opening
  
  -- Build all content in a single large buffer, then write in one go
  -- This is more efficient than thousands of small putStr calls
  let mut buffer : String := ""
  let mut lineCount := 0
  let mut partCount := 0
  
  for (n, is) in graph do
    let nodeLine := s!"  \"{n}\";\n"
    buffer := buffer ++ nodeLine

    -- Then add edges
    for i in is do
      let edgeLine := s!"  \"{i}\" -> \"{n}\";\n"
      buffer := buffer ++ edgeLine
    
    lineCount := lineCount + is.size + 1
    
    -- Write buffer when it reaches ~10MB to prevent unbounded memory growth
    if buffer.length > 10_000_000 then
      handle.putStr buffer
      partCount := partCount + 1
      if partCount % 5 == 0 then
        IO.eprintln s!"[DEBUG-WRITE] Wrote {partCount} parts ({partCount * 10}MB+ so far)"
      _ ← handle.flush
      buffer := ""
  
  -- Write any remaining buffered content
  if buffer.length > 0 then
    handle.putStr buffer
    _ ← handle.flush
  
  handle.putStrLn "}"
  _ ← handle.flush

/--
>>>>>>> 610c170 (fixed I/O bottlenecks)
Write an import graph, represented as a `NameMap (Array Name)` to the ".dot" graph format.
<<<<<<< HEAD
* Nodes in the `unused` set will be shaded light gray.
* If `markedPackage` is provided:
  * Nodes which start with the `markedPackage` will be highlighted in green and drawn closer together.
  * Edges from `directDeps` into the module are highlighted in green
  * Nodes in `directDeps` are marked with a green border and green text.
  * Nodes in `withSorry` are highlighted in gold.
=======

Note: For very large graphs (1M+ edges), consider using `writeDotGraph` instead
to stream directly to a file and avoid memory issues.
>>>>>>> ccf9d1a (Remove visualization attributes from DOT exports)
-/
def asDotGraph
    (graph : NameMap (Array Name))
    (_unused : NameSet := ∅)
    (header := "import_graph")
    (_markedPackage : Option Name := none)
    (_withSorry : NameSet := ∅)
    (_directDeps : NameSet := ∅)
    (_from_ _to : NameSet := ∅):
    String := Id.run do
  let mut lines := #[s!"digraph \"{header}\" " ++ "{"]
  for (n, is) in graph do
    lines := lines.push s!"  \"{n}\";"
    -- Then add edges
    for i in is do
      lines := lines.push s!"  \"{i}\" -> \"{n}\";"
  lines := lines.push "}"
  return "\n".intercalate lines.toList
