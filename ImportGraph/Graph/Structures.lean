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
Structure inheritance graph showing parent-child relationships
between structures and typeclasses, including field/parameter dependencies.
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
from the structures graph.
-/
private def isPrivateDeclaration (name : Name) : Bool :=
  name.isInternalDetail

/--
Extract structure/class names from an expression by walking its structure.
This is a simple syntactic traversal without full type inference.
-/
private def extractStructuresFromExpr (env : Environment) (e : Expr) : NameSet := 
  let rec walk (expr : Expr) (acc : NameSet) : NameSet :=
    match expr with
    | Expr.const n _ =>
      if Lean.getStructureInfo? env n |>.isSome then
        acc.insert n
      else
        acc
    | Expr.app f a =>
      walk a (walk f acc)
    | Expr.forallE _ t b _ =>
      walk b (walk t acc)
    | Expr.lam _ t b _ =>
      walk b (walk t acc)
    | _ => acc
  walk e ∅

/--
Extract field/parameter dependencies from a structure's constructor type.
Walks the constructor signature to find structure/class references in field types.
-/
private def getFieldDependencies (env : Environment) (structName : Name) : Array Name := Id.run do
  -- Try to access the constructor's type
  let ctorName := structName.append `mk
  match env.find? ctorName with
  | none => return #[]
  | some info =>
    -- Extract structure names from the constructor type expression
    let fieldStructs := extractStructuresFromExpr env info.type
    -- Remove the structure itself to avoid self-loops
    let filtered := fieldStructs.erase structName
    return filtered.toArray

/--
Build the structure/typeclass inheritance graph.

For each structure in the environment with parent structures, create edges.
This captures the inheritance relationships for both typeclasses and regular structures,
and includes field/parameter dependencies.

Parameters:
- `env`: The Lean environment to analyze

Returns a `NameMap (Array Name)` where:
- Key: A structure name that has parents or field dependencies
- Value: Array of parent structure names and field dependencies (deduplicated)
-/
public def structuresGraph (env : Environment) : CoreM (NameMap (Array Name)) := do
  let mut graph : NameMap (Array Name) := {}
  let mut allReferencedStructures : NameSet := {}
  
  -- First pass: collect all structures and their dependencies
  let mut structureDeps : NameMap (Array Name) := {}
  for (name, _) in env.constants.toList do
    if isPrivateDeclaration name then continue
    
    if let some _sinfo := Lean.getStructureInfo? env name then
      let parents := getParentStructures env name
      let fields := getFieldDependencies env name
      let allDeps := (parents ++ fields).foldl (init := NameSet.empty) (·.insert ·)
      let filteredDeps : Array Name := allDeps.toArray.filter (!isPrivateDeclaration ·)
      
      if filteredDeps.size > 0 then
        structureDeps := structureDeps.insert name filteredDeps
        -- Track all structures that are referenced
        for dep in filteredDeps do
          allReferencedStructures := allReferencedStructures.insert dep
  
  -- Second pass: include all structures that have dependencies OR are dependencies of others
  for (name, _) in env.constants.toList do
    if isPrivateDeclaration name then continue
    
    if let some _sinfo := Lean.getStructureInfo? env name then
      -- Include if: (1) has outgoing deps, OR (2) is referenced by others
      if structureDeps.contains name || allReferencedStructures.contains name then
        if let some deps := structureDeps.find? name then
          graph := graph.insert name deps
        else
          -- Referenced by others but has no outgoing deps - add with empty deps
          graph := graph.insert name #[]
  
  return graph

end Lean.Environment
