import LeanGraph.Imports.FromSource

/-!
# Tests for Source-Based Import Analysis

Tests for `findImportsFromSource` and `findTransitiveImportsFromSource`.
-/

open Lean System

-- Test basic import parsing
/-- info: #[`LeanGraphTest.Unused] -/
#guard_msgs in
#eval do
  let imports ← findImportsFromSource "LeanGraphTest/Used.lean"
  -- Filter to only LeanGraph modules
  return imports.filter (fun (n : Name) => n.getRoot ∈ [`LeanGraph, `LeanGraphTest])

-- Test transitive imports without filter
/-- info: #[`LeanGraphTest.Unused] -/
#guard_msgs in
#eval do
  let transitive ← findTransitiveImportsFromSource "LeanGraphTest/Used.lean"
  -- Filter to only LeanGraph modules
  let filtered := transitive.toArray.filter (fun (n : Name) => n.getRoot ∈ [`LeanGraph, `LeanGraphTest])
  return filtered.qsort Name.lt

-- Test transitive imports with LeanGraph filter
/-- info: #[] -/
#guard_msgs in
#eval do
  let transitive ← findTransitiveImportsFromSource "LeanGraphTest/Used.lean" (some `LeanGraph)
  return transitive.toArray.qsort Name.lt

-- Test on a file with transitive imports
/-- info: #[`LeanGraph.Tools.ImportDiff, `LeanGraphTest.Used] -/
#guard_msgs in
#eval do
  let imports ← findImportsFromSource "LeanGraphTest/FileWithTransitiveImports.lean"
  -- Filter to only LeanGraph modules
  return imports.filter (fun (n : Name) => n.getRoot ∈ [`LeanGraph, `LeanGraphTest])

/--
info: #[`LeanGraphTest.Unused, `LeanGraphTest.Used, `LeanGraph.Imports.LeanGraph, `LeanGraph.Tools.ImportDiff]
-/
#guard_msgs in
#eval do
  let transitive ← findTransitiveImportsFromSource "LeanGraphTest/FileWithTransitiveImports.lean"
  -- Filter to only LeanGraph modules
  let filtered := transitive.toArray.filter (fun (n : Name) => n.getRoot ∈ [`LeanGraph, `LeanGraphTest])
  return filtered.qsort Name.lt
