/-
Copyright (c) 2024 ImportGraph Contributors. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: ImportGraph Contributors
-/
module

public import Lean.Environment
public import Lean.CoreM
import Lean.Data.NameMap.Basic
import Lean.Structure

open Lean

/-
Structure inheritance hierarchy graph showing parent-child relationships
between structures and typeclasses.
-/

namespace Lean.Environment

/--
Get the parent structures of a structure/class by examining its structure info.
Returns an array of parent structure names.
-/
private def getParentStructures (env : Environment) (structName : Name) : Array Name := Id.run do
  if let some info := Lean.getStructureInfo? env structName then
    -- parentInfo contains the parent structures
    return info.parentInfo.map (·.structName)
  else
    return #[]

/--
Check if a name is a private/internal declaration that should be filtered
from the hierarchy graph.
-/
private def isPrivateDeclaration (name : Name) : Bool :=
  name.isInternalDetail

/--
Build the structure/typeclass hierarchy graph.

For each structure in the environment with parent structures, create edges.
This captures the inheritance hierarchy for both typeclasses and regular structures.

Parameters:
- `env`: The Lean environment to analyze

Returns a `NameMap (Array Name)` where:
- Key: A structure name that has parents
- Value: Array of parent structure names it extends
-/
public def hierarchyGraph (env : Environment) : CoreM (NameMap (Array Name)) := do
  let mut graph : NameMap (Array Name) := {}
  
  for (name, _) in env.constants.toList do
    -- Filter private declarations
    if isPrivateDeclaration name then continue
    
    -- Check if this is a structure with parent structures
    if let some sinfo := Lean.getStructureInfo? env name then
      if sinfo.parentInfo.size > 0 then
        let parents := getParentStructures env name
        -- Also filter private parents
        let filteredParents := parents.filter (!isPrivateDeclaration ·)
        if filteredParents.size > 0 then
          graph := graph.insert name filteredParents
  
  return graph

end Lean.Environment
