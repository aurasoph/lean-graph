/-
Copyright (c) 2026 Evan Wang. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Evan Wang
-/

-- Test fixtures (small Lean files for testing import structure)
import LeanGraphTest.AnotherFileWithTransitiveImports
-- import LeanGraphTest.Dot  -- TODO: Fix expected output comparison
import LeanGraphTest.FileWithTransitiveImports
import LeanGraphTest.FromSource
import LeanGraphTest.Imports
import LeanGraphTest.Unused
import LeanGraphTest.Used
import LeanGraphTest.ToTarget
import LeanGraphTest.WithSorry.Def
import LeanGraphTest.WithSorry.Thm

-- Test suites
import LeanGraphTest.RegressionTests
import LeanGraphTest.UnifiedGraphTests
import LeanGraphTest.FilteringTests

/-!
Test library. Contains test fixtures and regression tests.
-/
