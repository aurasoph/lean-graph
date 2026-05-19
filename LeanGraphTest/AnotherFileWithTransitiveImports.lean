import LeanGraph.Tools.ImportDiff
import LeanGraphTest.Unused
import LeanGraphTest.FileWithTransitiveImports

/--
info: The following are already imported (possibly transitively):
LeanGraphTest.FileWithTransitiveImports
---
info: Found 2 additional imports:
LeanGraphTest.FileWithTransitiveImports
LeanGraphTest.Used
-/
#guard_msgs in
#import_diff LeanGraphTest.FileWithTransitiveImports

/--
info: The following are already imported (possibly transitively):
LeanGraphTest.FileWithTransitiveImports
LeanGraphTest.Used
---
info: Found 2 additional imports:
LeanGraphTest.FileWithTransitiveImports
LeanGraphTest.Used
-/
#guard_msgs in
#import_diff LeanGraphTest.FileWithTransitiveImports LeanGraphTest.Used


/-- error: File SomeBogusFilename cannot be found. -/
#guard_msgs in
#import_diff SomeBogusFilename
