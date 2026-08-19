# ADR-0001: Native Rust matcher for search acceleration

- **Status**: accepted
- **Date**: 2026-08-19

## Context

Every keystroke in flash-cjk builds an alternation regex over large CJK
character classes. vim's regex engine scans each visible line against every
branch, and the cost grows with pattern length: measured 55–80 ms/keystroke
for long patterns on a 60-line window — visibly laggy while typing.
The project is a Neovim plugin written in Lua; no Lua-side fix (caching,
pattern pruning) removed the per-keystroke scan cost without changing
matching semantics.

## Decision

Add an optional native matcher: a Rust workspace (`flash-cjk-core` lib,
`flash-cjk-search` stdin/stdout JSON binary) that compiles the same
segmentations into per-alternative DP passes. The binary is spawned once per
keystroke; when absent or failing, the plugin transparently falls back to the
existing vim-regex path with identical behavior. Toolchain baseline: edition
2024, MSRV tracking latest stable (end users build via lazy.nvim's `build` hook).

## Alternatives Considered

### Thompson NFA / Aho-Corasick over all interpretations

- Pros: single automaton per keystroke.
- Cons: the alternation has no shared-prefix structure — every interpretation
  is an independent character-class chain — so a combined automaton degenerates
  into the same per-alternative scans with more setup cost.
- Why not chosen: measured DP already runs at 0.1–2.4 ms/keystroke; no headroom.

### Bit-parallel reachability (input × text bitsets)

- Pros: theoretical speedup on dense matches.
- Cons: adds complexity the measurements cannot justify; the simple DP is what
  the strict cross-validation can reason about.
- Why not chosen: no measurable problem to solve.

### Persistent daemon instead of per-keystroke spawn

- Pros: saves process startup per keystroke.
- Cons: process-lifecycle and async-bridging complexity in Neovim.
- Why not chosen: measured `vim.system` spawn, JSON, and search on 60 lines at
  **0.44 ms** per call (release build, table construction included); a daemon
  would save ~0.35 ms/keystroke at real maintenance cost.

## Consequences

- Long-input keystroke latency drops from 55–80 ms to ~1–3 ms end-to-end
  (3.8×–76× depending on pattern).
- Two matching implementations must stay behaviorally identical; the parity
  invariant is enforced by `tests/cross_validate_rust.lua` (strict equality +
  fuzz) and the e2e parity check. Every matcher change now touches two paths.
- Rust data tables are generated from the Lua source of truth
  (`scripts/export_rs.lua`) — the single-source pipeline must be used.
- The plugin's MSRV tracks latest stable, which affects end-user builds;
  downgrading support for older toolchains is an accepted trade-off here.
- CI and local toolchain now include a Rust component (mise-managed).

## Review Triggers

- `vim.system` spawn cost grows materially on large windows or many splits
  (revisit the daemon alternative with fresh measurements).
- flash.nvim exposes a native async matcher API that Lua could implement
  against directly.
- Neovim's regex engine gains a materially faster alternation path.
