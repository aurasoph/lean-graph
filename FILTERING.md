# Graph Filtering Guide

By default, the tool only shows human-written, documented code. You can also get the full graph including compiler machinery and internal details.

## Default Mode (Recommended)

```bash
lake exe graph --to Mathlib --mode unified output.dot
```

~46k declarations, ~1.1M edges. This is what most people want—it matches the Mathlib documentation exactly.

Filters out:
- Auto-generated junk (`eq_N`, `proof_N`, `match_N`, etc.)
- Internal/private stuff (prefixed with `_private` or `_`)
- Compiler machinery (recursors, NoConfusion, matchers)
- Anything without a docstring

Good for understanding module structure, mathematical dependencies, and refactoring planning.

## Exhaustive Mode (`--include-aux`)

```bash
lake exe graph --to Mathlib --mode unified --include-aux output.dot
```

~308k declarations, ~8.4M edges. Everything: auto-generated, internal, machinery, compiler artifacts.

Use this when you need to see *everything*: full refactoring, compliance audits, understanding how Lean generates code, migration planning.

## Quick Comparison

| | Default | Exhaustive |
|---|---------|-----------|
| **Nodes** | 46k | 308k (6.7x) |
| **Edges** | 1.1M | 8.4M (7.6x) |
| **Edge types** | 6 semantic types | Generic |
| **Speed** | ~5-10 min | ~30-60 min |
| **Use for** | Analysis | Full refactoring, audits |

## Examples

**Understand Nat usage:**
```bash
lake exe graph --to Mathlib --mode unified --edge-types proof,sig output.dot
```

**See internals too:**
```bash
lake exe graph --to Mathlib --mode unified --include-aux --edge-types proof,sig output.dot
```

**Refactoring: what must move together?**
```bash
lake exe graph --to Mathlib --mode unified --include-aux output.dot
```

**Compliance audit:**
```bash
lake exe graph --to Mathlib --mode unified --include-aux output.ndjson
```

## Edge Types (Filtered Mode)

Default mode distinguishes between edge types: **extends**, **field**, **sig**, **proof**, **def**, **docref**. This tells you *why* one thing depends on another. Exhaustive mode doesn't distinguish—just lumps everything together.

## How Filtering Works

Uses the same logic as [doc-gen4](https://github.com/leanprover-community/doc-gen4): include a declaration if it would appear in the Mathlib docs. No internal details, no auto-generated children, no private stuff.

## Performance Tips

- Default mode is ~2x faster than exhaustive
- DOT gets huge in exhaustive mode; use NDJSON for large graphs
- Use `--aggregate module` for file-level view
- Use `--edge-types proof,sig` to reduce noise
- Use `--from`/`--to` for sub-graphs
