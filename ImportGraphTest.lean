/-
Copyright (c) 2026 Evan Wang. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Evan Wang
-/

/-!
Test library. Contains test fixtures and regression tests.
-!/

-- Test fixtures (small Lean files for testing import structure)
import ImportGraphTest.AnotherFileWithTransitiveImports
import ImportGraphTest.Dot
import ImportGraphTest.FileWithTransitiveImports
import ImportGraphTest.FromSource
import ImportGraphTest.Imports
import ImportGraphTest.Unused
import ImportGraphTest.Used
import ImportGraphTest.ToTarget
import ImportGraphTest.WithSorry.Def
import ImportGraphTest.WithSorry.Thm

-- Test suites
import ImportGraphTest.RegressionTests
import ImportGraphTest.UnifiedGraphTests
import ImportGraphTest.FilteringTests
