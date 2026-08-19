# Architecture

This document orients new contributors and guards the design against
accidental drift — especially by AI agents making broad changes. Keep it short
and stable: a map of the country, not an atlas of its states. Revisit it
occasionally; do not try to keep it synchronized with the code.

## Overview

flash-cjk.nvim extends flash.nvim's jump flow with CJK matching: every
keystroke is segmented into interpretations (pinyin, romaji, romanized Korean,
literal ASCII) and compiled into a vim regex — or, when the optional native
binary is present, handed to a Rust DP matcher with identical semantics. A
custom labeler assigns labels that never collide with the user's next likely
input letter.

## Codebase Map

- `init.lua` — public API (`setup`/`jump`/`remote`) and orchestration; re-exports
  the config/match helpers tests and users rely on
- `config.lua` — configuration defaults, scheme registry, language-flag
  resolution (no flash.nvim dependency)
- `match.lua` — matching domain: segmentation parser, punctuation classes,
  language-lock markers, mixed-mode compiler
- `patches.lua` — flash.nvim patches (C-c dispatch, prompt lock display)
- `util.lua` — shared helpers
- `labeler.lua` — flash labeler: next-letter prediction (from spellings or the Rust matcher's per-match predictions), skip-set, monotonic label pool
- `rust.lua` — bridge to the native binary: per-keystroke spawn, JSON protocol, fallback circuit breaker to the vim-regex path
- data modules (`zhcnData.lua`, `jaData.lua`, `zhcnRev.lua`, `ja.lua`, `ko.lua`) — char-class tables and per-language pattern helpers; `jaData.lua` is generated
- `flash-cjk-core` (Rust lib) — charset, parser, DP matcher, prediction; mirrors Lua semantics
- `flash-cjk-search` (Rust binary) — stdin/stdout JSON front for the core
- `tests/` — behavior suite, strict rust↔vim cross-validation and fuzz, LazyVim-style e2e
- `scripts/` — data generators (Unihan → lua, lua → rust)

## Invariants

What must remain true about the architecture:

- **Parity**: the Rust matcher and the vim-regex path must produce identical
  matches (`searchpos` semantics: left-to-right, first alternative in compile
  order wins, spans never overlap). Enforced by `tests/cross_validate_rust.lua`
  and the e2e parity check; any matcher change updates both paths.
- **Data single source**: the Lua tables are the source of truth.
  `jaData.lua` is generated from Unihan (`scripts/gen_jp_data.py`); every
  Rust static table — Chinese, Japanese, Korean jamo and punctuation — is
  generated from the Lua tables by `scripts/export_rs.lua` into `rust/data/`
  and `rust/crates/flash-cjk-core/src/data/`. Generated files are never
  hand-edited.
- **Optional native path**: the binary's absence or repeated failure must
  transparently fall back to the vim-regex path with identical behavior.
  The labeler works unchanged on either path.
- **Marker/key decoupling**: language-lock markers are buffer-safe control
  bytes stored inside the pattern; the keys that trigger them are configurable
  and never enter the pattern themselves. The prompt shows readable tags via a
  display-only patch.
- **Dependency direction**: `flash-cjk-search` → `flash-cjk-core` only;
  the Lua side talks to the binary solely through the JSON protocol in
  `rust.lua`.

## Cross-Cutting Concerns

- Error handling: the Lua bridge never raises — every failure degrades to the
  fallback path; the binary uses `anyhow` at its boundary, the core lib exposes
  no error types.
- Performance: segmentation is bounded (`MAX_SEGMENTATIONS`); the labeler uses
  a union skip-set and a monotonic pool. Measure before optimizing further
  (benchmarks: `rust/crates/flash-cjk-core/benches/`).

## Decisions

Significant decisions are recorded as ADRs in [docs/adr/](./docs/adr/),
following the guidelines repository's `adr.template.md`. Start with
[ADR-0001: native Rust matcher](./docs/adr/0001-rust-native-matcher.md).
When a request conflicts with an ADR, do not silently violate it — raise it.
