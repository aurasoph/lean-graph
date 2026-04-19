/-
Copyright (c) 2024 ImportGraph Contributors. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: ImportGraph Contributors
-/
module

import Lean
import Lean.Meta.Basic
import Lean.PrettyPrinter
import Lean.Util.PPExt
import Lean.DocString
import Cli.Basic
import ImportGraph.Graph.FilterCommon
import ImportGraph.Lean.WithImportModules
import ImportGraph.Util.CurrentModule

/-!
# `lake exe export_statements`

Exports every explicit Lean declaration in the target module as a JSONL file:
```
{"name":"Nat.add_comm","module":"Init.Data.Nat.Basic","decl_type":"theorem",
 "signature":"Nat.add_comm : ∀ (n m : ℕ), n + m = m + n"}
```

Pairs with `unified.db` for LLM-based English definition generation.
-/

open Lean Meta PrettyPrinter Cli

/-- Escape a string for JSON embedding. -/
private def jsonEscape (s : String) : String :=
  s.foldl (fun acc c =>
    match c with
    | '\\' => acc ++ "\\\\"
    | '"'  => acc ++ "\\\""
    | '\n' => acc ++ "\\n"
    | '\r' => acc ++ "\\r"
    | '\t' => acc ++ "\\t"
    | c    => acc.push c) ""

/-- Classify a declaration kind as a short label. -/
private def declTypeLabel (env : Environment) (name : Name) (info : ConstantInfo) : String :=
  if let some _ := Lean.getStructureInfo? env name then "structure"
  else if Lean.isStructure env name then "structure"
  else match info with
    | .thmInfo _    => "theorem"
    | .defnInfo _   => "definition"
    | .axiomInfo _  => "axiom"
    | .inductInfo _ => "inductive"
    | .ctorInfo _   => "constructor"
    | _             => "other"

/-- Get the root namespace component of a `Name` (e.g. `Mathlib.Algebra.Group` → `Mathlib`). -/
private def nameRoot : Name → Name
  | .str .anonymous s => .str .anonymous s
  | .num .anonymous n => .num .anonymous n
  | .str parent _    => nameRoot parent
  | .num parent _    => nameRoot parent
  | .anonymous       => .anonymous

/--
Decide whether a declaration should appear in the exported statements file.
Matches `shouldIncludeConstant` exactly: doc-gen4 aligned filter.
Pass `includeAll := true` for exhaustive/debug export.
-/
private def shouldIncludeForExport (env : Environment) (name : Name)
    (includeAll : Bool) : Bool :=
  Lean.Environment.shouldIncludeConstant env name includeAll

/--
Try to get the pretty-printed signature string for `name`.
Returns `none` if pretty-printing fails.
-/
private def tryGetSignature (name : Name) (ctx : Core.Context) (s : Core.State)
    : IO (Option String) := do
  try
    let (fmtWithInfos, _) ← (MetaM.run' (ppSignature name)).toIO ctx s
    return some (fmtWithInfos.fmt.pretty 120)
  catch _ => return none

def exportStatementsCLI (args : Parsed) : IO UInt32 := do
  let to ← match args.flag? "to" with
    | some flag => pure <| flag.as! (Array ModuleName)
    | none      => pure #[← ImportGraph.getCurrentModule]
  initSearchPath (← findSysroot)

  let outFile      := (args.flag? "output" |>.map (·.as! String)).getD "statements.jsonl"
  let includeInfra := args.hasFlag "include-infra"
  let includeAll   := args.hasFlag "include-aux"

  unsafe Lean.enableInitializersExecution
  unsafe withImportModules (to.map ({module := ·})) {} (trustLevel := 1024) fun env => do
    let ctx   : Core.Context := { options := {}, fileName := "<input>", fileMap := default }
    let state : Core.State   := { env }

    -- Positive module filter: allow root namespaces of --to modules plus core libraries.
    -- Always includes Init (Lean core), Std (standard library), Lean (core types),
    -- and Batteries (extra lemmas). Use --include-infra to also get Qq, Plausible, etc.
    let allowedRoots : Array Name :=
      (to.map nameRoot) ++ [`Init, `Std, `Lean, `Batteries]

    let handle ← IO.FS.Handle.mk ⟨outFile⟩ IO.FS.Mode.write
    let mut count   := 0
    let mut skipped := 0

    for (name, constInfo) in env.constants.toList do
      -- Skip anonymous, internal, macro-scoped names
      if name == .anonymous || name.isInternal || name.hasMacroScopes then
        skipped := skipped + 1
      else
        if !shouldIncludeForExport env name includeAll then
          skipped := skipped + 1
        else
          -- Resolve defining module
          let modName : Name := match env.getModuleIdxFor? name with
            | some idx => env.header.moduleNames[idx.toNat]!
            | none     => .anonymous
          let modStr := modName.toString

          -- Positive module filter: skip unless module root is in allowedRoots.
          let isAllowed := includeInfra || allowedRoots.any (fun r => r.isPrefixOf modName)
          if !isAllowed then
            skipped := skipped + 1
          else
            -- Pretty-print the signature
            let sigOpt ← tryGetSignature name ctx state
            match sigOpt with
            | none =>
              skipped := skipped + 1
            | some sig =>
              let dtype     := declTypeLabel env name constInfo
              let docstring := ((← Lean.findDocString? env name).getD "")
              let line  := s!"\{\"name\":\"{jsonEscape name.toString}\"," ++
                            s!"\"module\":\"{jsonEscape modStr}\"," ++
                            s!"\"decl_type\":\"{dtype}\"," ++
                            s!"\"signature\":\"{jsonEscape sig}\"," ++
                            s!"\"docstring\":\"{jsonEscape docstring}\"}"
              handle.putStrLn line
              count := count + 1
              if count % 10000 == 0 then
                IO.eprintln s!"[ExportStatements] {count} exported..."

    IO.eprintln s!"[ExportStatements] Done: {count} exported, {skipped} skipped → {outFile}"
  return 0

def exportStatements : Cmd := `[Cli|
  export_statements VIA exportStatementsCLI; ["0.0.1"]
  "Export all explicit Lean declarations with pretty-printed signatures to JSONL. \
   Pairs with unified.db for LLM-based English definition generation. \
   Run from inside a Mathlib checkout: lake exe export_statements --to Mathlib"

  FLAGS:
    "to"            : Array ModuleName; "Module(s) to export (default: current module)."
    "output"        : String;           "Output JSONL file path (default: statements.jsonl)."
    "include-aux";                      "Include all declarations (exhaustive mode, bypasses doc-aligned filter)."
    "include-infra";                    "Disable module filter; include all namespaces (Lean, Std, Batteries, Qq, etc.)."
]

/-- `lake exe export_statements` -/
public def main (args : List String) : IO UInt32 :=
  exportStatements.validate args
