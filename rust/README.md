# flash-cjk Rust matcher

An optional native matcher that replaces the vim-regex search path with
a compiled binary. Built once, it is detected automatically at jump
time; when absent (or after repeated failures) the plugin transparently
falls back to the pure-Lua vim-regex path.

## Why

Every keystroke in flash-cjk builds an alternation regex over large
CJK character classes. vim's regex engine scans each visible line
against every branch, and the cost grows with pattern length
(55-80 ms/keystroke for long patterns on a 60-line window). The Rust
matcher compiles the same segmentations into per-alternative DP passes
over the text: ~0.1-2.4 ms/keystroke for the same inputs, and longer
patterns get _faster_ (fewer matches), not slower.

Measured end-to-end (60-line mixed CJK window, full flash `State`
pipeline incl. spawning the binary per keystroke):

| pattern | vim-regex | rust   | speedup |
| ------- | --------- | ------ | ------- |
| `n`     | 16.4 ms   | 4.3 ms | 3.8x    |
| `ni`    | 20.6 ms   | 2.4 ms | 8.7x    |
| `nih`   | 80.7 ms   | 1.8 ms | 45x     |
| `kim`   | 55.2 ms   | 0.7 ms | 76x     |

## Build

```sh
cd rust
cargo build --release
```

The binary lands in `rust/target/release/flash-cjk-search`; nothing
else needs to be configured -- `require("flash-cjk.rust").available()`
locates it relative to the plugin source tree.

## Layout

```
rust/
  Cargo.toml              workspace
  crates/
    flash-cjk-core/       library: matching core
      src/charset.rs      character sets (sorted / ranges / single)
      src/data.rs         embedded tables + Korean arithmetic builder
      src/parser.rs       pattern segmentation (mirrors init.lua)
      src/matcher.rs      DP matching, vim searchpos semantics
      src/predict.rs      labeler next-letter prediction
      tests/, benches/    cross checks and criterion benchmarks
    flash-cjk-search/     the stdin/stdout JSON binary
  data/                   generated Rust data (from scripts/export_rs.lua)
```

The generated data under `rust/data/` comes from the Lua modules -- the
single source of truth. Regenerate with:

```sh
nvim -l scripts/export_rs.lua
```

## Alternatives considered

- **Thompson NFA / Aho-Corasick over all interpretations**: the
  alternation has no shared-prefix structure to exploit (every
  interpretation is an independent character-class chain), so a
  combined automaton degenerates into the same per-alternative scans
  the DP already performs, with more setup cost per keystroke.
- **Bit-parallel reachability (input-position x text-position
  bitsets)**: measured per-alternative DP at 0.1-2.4 ms/keystroke on a
  60-line window -- far below anything bit-parallelism would improve
  meaningfully, and the simple formulation is exactly what the strict
  cross-validation can reason about.
- **Persistent daemon instead of per-keystroke spawn**: measured
  `vim.system` spawn, JSON, and search on 60 lines at **0.44 ms** per
  call (release build); a daemon would save ~0.35 ms/keystroke while
  adding process-lifecycle and async-bridging complexity. Rejected on
  measurement. Note: each spawned process rebuilds its tables from the
  embedded data; that build is included in the 0.44 ms.

Steady-state keystroke profile (60-line window, 100 matches, warm
state, after the labeler union-set optimization):

| phase                            | ms       |
| -------------------------------- | -------- |
| rust matcher (spawn + JSON + DP) | 0.6      |
| labeler (skip + assignment)      | 1.4      |
| highlight                        | 0.3      |
| flash state machinery            | 0.8      |
| **total**                        | **~3.1** |

The remaining floor is flash's own per-match pipeline, which the
vim-regex path pays identically. With multiple visible windows flash
calls the matcher once per window, so each extra split adds one
binary invocation (~0.44 ms); a two-split layout still measures well
under the single-window vim-regex cost.

## Protocol

One JSON request on stdin, one JSON response on stdout:

```jsonc
// request
{ "pattern": "ti", "lines": ["日本語…"],
  "langs": { "cn": true, "jp": true, "ko": true,
             "en": true, "alpha_mixing": true } }
// response
{ "matches": [[line, col, end_col, len]],   // byte cols; end_col = last char start
  "predictions": ["k", "tc", …] }           // per-match next letters for the labeler
```

`matches` follow vim `searchpos` semantics (left-to-right, first
alternative in compile order wins, spans never overlap), which the
strict cross-validation suite (`tests/cross_validate_rust.lua`)
asserts item-by-item against the vim-regex implementation.

## Testing

```sh
cd rust
cargo test                 # unit + cross checks
cargo bench                # criterion benchmarks (keystroke/matching.rs)
cargo clippy --all-targets # zero warnings
cargo fmt --all --check
```
