/-
Copyright (c) 2026 Evan Wang. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Evan Wang
-/
module

public import Lean.Environment
public import Lean.CoreM
import Lean.DeclarationRange
import Lean.Data.NameMap.Basic
import Lean.Parser.Module

open Lean

/-!
# Minimal self-contained library export

Given a target declaration, emit the source text of exactly the declarations it
transitively needs from a set of *target modules*, in dependency order, as a file
that does not import those modules. Everything outside the target modules (core
Lean, or a declared base) is assumed available from the prelude / a base import.

Method:
- `rawClosure`: transitive `getUsedConstants` over each constant's type AND value
  (the faithful kernel closure, matching lean4export's dependency discipline).
- Parse each contributing module with the Lean frontend into its top-level
  *command* syntax nodes (using the loaded environment so custom notation parses).
- Emit (a) every declaration-command whose source span contains a needed
  declaration — the command span carries the declaration's attributes and
  docstring — and (b) every notation / macro / syntax command from the module,
  which the source text needs but the kernel closure never records.
- Order by module import index, then source position (dependency order).

The emitted file compiling standalone is the faithfulness test for the closure.
-/

namespace LeanGraph.MinimalLibrary

/-- Raw transitive closure over `getUsedConstants` of a constant's type AND value. -/
public partial def rawClosure (env : Environment) (target : Name) : NameSet := Id.run do
  let mut visited : NameSet := {}
  let mut stack : Array Name := #[target]
  while !stack.isEmpty do
    let n := stack.back!
    stack := stack.pop
    if visited.contains n then continue
    visited := visited.insert n
    if let some info := env.find? n then
      let mut deps := info.type.getUsedConstants
      if let some v := info.value? then deps := deps ++ v.getUsedConstants
      -- An inductive's constructor types carry dependencies absent from the
      -- inductive's own type (e.g. `RBNode.WF.insert` mentions `RBNode.insert`);
      -- the extracted `inductive` command needs them, so pull the constructors in.
      if let .inductInfo val := info then
        deps := deps ++ val.ctors.toArray
      for d in deps do
        if !visited.contains d then stack := stack.push d
  return visited

/-- Module index that defines `n` (lower = imported earlier = dependency). -/
public def moduleIdxOf (env : Environment) (n : Name) : Option Nat :=
  (env.getModuleIdxFor? n).map (·.toNat)

/-- Module that defines `n`, when `n` comes from an imported module. -/
public def moduleNameOf (env : Environment) (n : Name) : Option Name := do
  let idx ← env.getModuleIdxFor? n
  env.header.moduleNames[idx.toNat]?

/-- Lexicographic ≤ on source positions. -/
def posLE (a b : Position) : Bool := a.line < b.line || (a.line == b.line && a.column ≤ b.column)

/-- Does range `(ap,ae)` strictly contain `(bp,be)`? -/
def strictlyContains (ap ae bp be : Position) : Bool :=
  posLE ap bp && posLE be ae && (ap != bp || ae != be)

/-- Slice `src` between two source positions (1-based line, 0-based codepoint column). -/
public def sliceByPos (src : String) (sp ep : Position) : String := Id.run do
  let lines := (src.splitOn "\n").toArray
  if sp.line == ep.line then
    return (((lines[sp.line - 1]!).drop sp.column).take (ep.column - sp.column)).toString
  let mut parts : Array String := #[((lines[sp.line - 1]!).drop sp.column).toString]
  for i in [sp.line : ep.line - 1] do
    parts := parts.push lines[i]!
  parts := parts.push (((lines[ep.line - 1]!).take ep.column)).toString
  return String.intercalate "\n" parts.toList

/-- Does `pat` occur in `s`? -/
def containsSubstr (s pat : String) : Bool := (s.splitOn pat).length ≥ 2

/-- Notation / macro / syntax commands provide surface syntax the kernel closure
never records, so the extracted source needs them carried along verbatim. -/
def isNotationLike (cmd : Syntax) : Bool :=
  let k := cmd.getKind.toString
  ["notation", "mixfix", "macro", "syntax", "prefix", "infix", "postfix"].any (containsSubstr k ·)

def isDeclaration (cmd : Syntax) : Bool := cmd.isOfKind ``Lean.Parser.Command.declaration

/-- Scope commands (`namespace`/`section`/`end`) are kept verbatim so extracted
declarations land in their real namespaces and the block structure stays balanced. -/
def isScopeCommand (cmd : Syntax) : Bool :=
  cmd.isOfKind ``Lean.Parser.Command.namespace ||
  cmd.isOfKind ``Lean.Parser.Command.section ||
  cmd.isOfKind ``Lean.Parser.Command.end

/-- All identifiers mentioned anywhere in a syntax node. -/
partial def collectIdents (stx : Syntax) (acc : Array Name) : Array Name :=
  match stx with
  | .ident _ _ n _ => acc.push n
  | .node _ _ args => args.foldl (fun a s => collectIdents s a) acc
  | _ => acc

/-- A command is safe to carry only if every constant it references is already in
the closure; otherwise it would dangle on a name we did not emit. (Identifiers
that are not constants — notation tokens, namespaces — are ignored.) -/
def refsInClosure (env : Environment) (closure : NameSet) (cmd : Syntax) : Bool :=
  (collectIdents cmd #[]).all fun n => !env.contains n || closure.contains n

/-- Scoping/context commands whose effect the extracted source may rely on
(`variable`/`open`/`set_option`/`universe`/`attribute`). Carried when their
referenced constants are all in the closure. -/
def isContextCommand (cmd : Syntax) : Bool :=
  let k := cmd.getKind.toString
  ["variable", "Command.open", "set_option", "universe", "Command.attribute"].any (containsSubstr k ·)

/-- Parse a module source into its top-level commands with source spans, using
`env` so the module's own notation parses correctly. -/
public def parseCommands (env : Environment) (src fileName : String) :
    IO (Array (Syntax × Position × Position)) := do
  let ictx := Parser.mkInputContext src fileName
  let (_, s, msgs0) ← Parser.parseHeader ictx
  let pmctx : Parser.ParserModuleContext := { env := env, options := {} }
  let mut state := s
  let mut msgs := msgs0
  let mut out : Array (Syntax × Position × Position) := #[]
  for _ in [0:1000000] do
    let (cmd, state', msgs') := Parser.parseCommand ictx pmctx state msgs
    state := state'; msgs := msgs'
    if cmd.isOfKind ``Lean.Parser.Command.eoi then break
    match cmd.getPos?, cmd.getTailPos? with
    | some p, some t =>
      out := out.push (cmd, ictx.fileMap.toPosition p, ictx.fileMap.toPosition t)
    | _, _ => pure ()
  return out

/-- Transitive imports of `root` (including `root`), via the module import graph. -/
public def transitiveImports (env : Environment) (root : Name) : NameSet := Id.run do
  let names := env.header.moduleNames
  let data := env.header.moduleData
  let mut nameToIdx : NameMap Nat := {}
  for i in [0:names.size] do
    nameToIdx := nameToIdx.insert names[i]! i
  let mut visited : NameSet := {}
  let mut stack : Array Name := #[root]
  while !stack.isEmpty do
    let m := stack.back!
    stack := stack.pop
    if visited.contains m then continue
    visited := visited.insert m
    if let some i := nameToIdx.find? m then
      for imp in data[i]!.imports do
        if !visited.contains imp.module then stack := stack.push imp.module
  return visited

/-- Modules auto-available in any `.lean` file: the transitive imports of the
root `Init` module. Constants from these need no `import`. -/
public def preludeModules (env : Environment) : NameSet := transitiveImports env `Init

/-- Emit the minimal self-contained source for `target`.

Declaration extents come from `declRangeExt` (accurate, including docstrings and
multi-line proofs); the parser is used only to harvest notation/macro/syntax
commands, which the source text needs but the kernel closure never records. -/
public def minimalExport (env : Environment) (target : Name) (targetModules : Array Name)
    (srcRoots : SearchPath) : IO String := do
  let closure := rawClosure env target
  -- Needed declaration ranges, grouped by defining module.
  -- A module is a target if it equals or lies under one of `targetModules`
  -- (so `Batteries` matches every `Batteries.*` module; everything else is base).
  let inTargets := fun (m : Name) => targetModules.any fun t => t == m || t.isPrefixOf m
  let mut neededByModule : NameMap (Array (Position × Position)) := {}
  for n in closure.toList do
    match moduleNameOf env n, Lean.declRangeExt.find? env n with
    | some m, some dr =>
      if inTargets m then
        let arr := (neededByModule.find? m).getD #[]
        neededByModule := neededByModule.insert m (arr.push (dr.range.pos, dr.range.endPos))
    | _, _ => pure ()
  -- Contributing modules, ordered by import index (dependencies first).
  -- Order contributing modules so dependencies come first: a module that
  -- transitively imports fewer modules is a dependency of ones that import more.
  let importCount : NameMap Nat := (neededByModule.toList.map (·.1)).foldl
    (fun m mod => m.insert mod (transitiveImports env mod).toList.length) {}
  let mods := (neededByModule.toList.map (·.1)).toArray.qsort fun a b =>
    (importCount.find? a).getD 0 < (importCount.find? b).getD 0
  -- Base imports: modules of closure constants that are neither extracted (a
  -- target module) nor part of the auto-imported prelude (`Init`). These come
  -- from the library's dependencies (e.g. Lean's `Std`) and are imported rather
  -- than inlined.
  let prelude := preludeModules env
  let mut baseImports : NameSet := {}
  for n in closure.toList do
    if let some m := moduleNameOf env n then
      if !inTargets m && !prelude.contains m then baseImports := baseImports.insert m
  let importMods := baseImports.toList.toArray.qsort (·.toString < ·.toString)
  let importStr := String.intercalate "\n" (importMods.toList.map (fun m => s!"import {m}"))
  let mut out : String :=
    s!"-- Minimal self-contained export of `{target}`.\n-- Generated by lean-graph.\n\n"
      ++ (if importMods.isEmpty then "" else importStr ++ "\n\n")
  for m in mods do
    let path ← findLean srcRoots m
    let src ← IO.FS.readFile path
    let needed := (neededByModule.find? m).getD #[]
    -- Top-level declaration commands: keep the maximal ranges (collapsing
    -- constructors / projections / recursors / equation lemmas into their command).
    let declSpans := needed.filter fun (ds, de) =>
      !needed.any fun (ps, pe) => strictlyContains ps pe ds de
    -- Context commands: scope (`namespace`/`section`/`end`) kept verbatim, and
    -- notation/macro kept when every constant it references is in the closure.
    let parsed ← parseCommands env src path.toString
    let contextSpans := parsed.filterMap fun (cmd, cs, ce) =>
      if isScopeCommand cmd ||
         ((isNotationLike cmd || isContextCommand cmd) && refsInClosure env closure cmd)
      then some (cs, ce) else none
    -- Emit all spans in source order, de-duplicated.
    let spans := ((declSpans ++ contextSpans).toList.eraseDups).toArray.qsort fun a b =>
      posLE a.1 b.1 && (a.1 != b.1 || posLE a.2 b.2)
    for (sp, ep) in spans do
      out := out ++ (sliceByPos src sp ep) ++ "\n\n"
  return out

end LeanGraph.MinimalLibrary
