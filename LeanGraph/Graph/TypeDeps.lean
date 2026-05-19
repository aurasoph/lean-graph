/-
Copyright (c) 2024 LeanGraph Contributors. All rights reserved.
Modifications (c) 2026 Evan Wang. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: LeanGraph Contributors
-/
module

public import Lean.Environment
public import Lean.CoreM
public import LeanGraph.Graph.FilterCommon
public import LeanGraph.Types
import Lean.Data.NameMap.Basic
import Lean.Meta.Match.MatcherInfo
import Lean.Structure

open Lean Meta
open LeanGraph.Types

/-!
# Type Dependency Graph (Blueprint Mode)

Extracts dependency edges from type signatures with rich per-edge metadata:
- `position`: whether the dependency appears in the conclusion or a hypothesis
- `binderKind`: explicit / implicit / instance / strict (relevant for hypothesis deps)
- `appRole`: whether the constant is in function or argument position
- `viaProj`: whether the dependency was accessed through field projection
-/

namespace Lean.Environment

private structure SigCtx where
  position   : SigPosition  := .conclusion
  binderKind : BinderInfo   := .default
  appRole    : AppRole      := .arg
  viaProj    : Bool         := false

private def toBinderKind : BinderInfo → BinderKind
  | .default => .explicit | .implicit => .implicit
  | .strictImplicit => .strictImplicit | .instImplicit => .instImplicit

private def SigCtx.meta (ctx : SigCtx) : SigEdgeMeta :=
  { position := ctx.position, binderKind := toBinderKind ctx.binderKind,
    appRole := ctx.appRole, viaProj := ctx.viaProj }

private def recordDep (name : Name) (ctx : SigCtx)
    (acc : NameMap SigEdgeMeta) : NameMap SigEdgeMeta :=
  match acc.find? name with
  | none          => acc.insert name ctx.meta
  | some existing => acc.insert name (existing.merge ctx.meta)

private def collectDeps (e : Expr) (ctx : SigCtx)
    (acc : NameMap SigEdgeMeta) : NameMap SigEdgeMeta :=
  match e with
  | .const name _       => recordDep name ctx acc
  | .forallE _ dom body bi =>
    let hypCtx  : SigCtx := { position := .hyp, binderKind := bi, appRole := .arg, viaProj := ctx.viaProj }
    let bodyCtx : SigCtx := { ctx with position := .conclusion }
    collectDeps body bodyCtx (collectDeps dom hypCtx acc)
  | .app fn arg =>
    collectDeps arg { ctx with appRole := .arg }
      (collectDeps fn { ctx with appRole := .fn } acc)
  | .proj typeName _ struct =>
    let acc' := recordDep typeName { ctx with viaProj := true } acc
    collectDeps struct { ctx with viaProj := true } acc'
  | .lam _ dom body _  =>
    collectDeps body ctx (collectDeps dom ctx acc)
  | .letE _ t v body _ =>
    collectDeps body ctx (collectDeps v ctx (collectDeps t ctx acc))
  | .mdata _ inner      => collectDeps inner ctx acc
  | _                   => acc  -- bvar, fvar, sort, lit, mvar

private def getTypeDepEdges (_env : Environment) (_name : Name) (info : ConstantInfo) :
    NameMap SigEdgeMeta :=
  collectDeps info.type {} {}

private def filterSigEdges (env : Environment) (edges : NameMap SigEdgeMeta)
    (includeAll : Bool) : Array (Name × SigEdgeMeta) := Id.run do
  let mut result : Array (Name × SigEdgeMeta) := #[]
  let mut seen : NameSet := {}
  for (name, em) in edges.toList do
    if seen.contains name then continue
    if shouldIncludeConstant env name includeAll then
      result := result.push (name, em)
      seen := seen.insert name
    else
      let parent := getParentDeclaration env name
      if parent != name && env.contains parent &&
         shouldIncludeConstant env parent includeAll &&
         !seen.contains parent then
        result := result.push (parent, em)
        seen := seen.insert parent
  return result

public def typeDepsGraph (env : Environment) (includeAll : Bool := false) :
    CoreM (NameMap (Array (Name × SigEdgeMeta))) := do
  let mut graph : NameMap (Array (Name × SigEdgeMeta)) := {}
  for (name, info) in env.constants.toList do
    if shouldIncludeConstant env name includeAll then
      let raw  := getTypeDepEdges env name info
      let deps := filterSigEdges env raw includeAll
      graph := graph.insert name deps
  return graph

end Lean.Environment
