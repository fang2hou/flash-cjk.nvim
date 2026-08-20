# flash-cjk Rust matcher

An optional native matcher that replaces the vim-regex search path with
a compiled binary. Built once, it is detected automatically at jump
time; on Unix a persistent server process keeps the matcher resident,
and when absent (or after repeated failures) the plugin transparently
falls back to the per-keystroke spawn transport and then to the
pure-Lua vim-regex path. See
[ADR-0003](../docs/adr/0003-persistent-matcher-server.md) for the
server lifecycle.

## Why

Every keystroke in flash-cjk builds an alternation regex over large
CJK character classes. vim's regex engine scans each visible line
against every branch, and the cost grows with pattern length
(55-80 ms/keystroke for long patterns on a 60-line window). The Rust
matcher compiles the same segmentations into per-alternative DP passes
over the text: ~0.1-2.4 ms/keystroke for the same inputs, and longer
patterns get _faster_ (fewer matches), not slower.

Measured on the full 15-combination matrix (1,050 generated windows,
M4 Pro, per-keystroke cost incl. the transport):

| series       | mean   | p50    | p95     |
| ------------ | ------ | ------ | ------- |
| vim-regex    | 8.1 ms | 0.4 ms | 30.1 ms |
| rust, spawn  | 9.6 ms | 8.9 ms | 12.8 ms |
| rust, server | 1.0 ms | 0.2 ms | 4.3 ms  |

The spawn transport pays ~0.9 ms process creation + ~8.2 ms data-table
startup on every keystroke; the server pays them once at startup and
then ~0.04 ms per UDS round trip.

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
    flash-cjk-search/     the JSON binary: stdin/stdout one-shot mode
                          + `serve` UDS server mode
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
- **Persistent daemon instead of per-keystroke spawn**: originally
  rejected on a 0.44 ms micro-measurement that missed the binary's
  table startup. Re-measured end-to-end at 9.6 ms/keystroke, reversed
  in [ADR-0003](../docs/adr/0003-persistent-matcher-server.md): the
  server keeps the matcher resident with connection-based liveness and
  a grace-period self-exit — no polling, no signals, no config.

Steady-state keystroke profile (60-line window, 100 matches, warm
state, after the labeler union-set optimization):

| phase                           | ms       |
| ------------------------------- | -------- |
| rust matcher (UDS request + DP) | 0.2-2.5  |
| labeler (skip + assignment)     | 1.4      |
| highlight                       | 0.3      |
| flash state machinery           | 0.8      |
| **total**                       | **~3.1** |

The remaining floor is flash's own per-match pipeline, which the
vim-regex path pays identically. With multiple visible windows flash
calls the matcher once per window; each extra split adds one UDS
round trip (~0.04 ms floor).

## Protocol

Two modes share one response shape.

One-shot: one JSON request on stdin, one JSON response on stdout (the
per-keystroke spawn transport):

```jsonc
// request
{ "pattern": "ti", "lines": ["日本語…"],
  "langs": { "zhcn": true, "ja": true, "ko": true,
             "en": true, "mixed_input": true } }
// response
{ "matches": [[line, col, end_col, len]],   // byte cols; end_col = last char start
  "predictions": ["k", "tc", …],            // per-match next letters for the labeler
  "pred_langs": [["ja"], …] }               // per-match attributed languages
```

Serve: `flash-cjk-search serve --socket <path> [--log <path>]` — one
NDJSON request per line per connection; the envelope adds `pid`
(diagnostics only) and `cmd`:

```jsonc
{ "cmd": "hello", "pid": 4242 }  // register this connection as a client session
{ "cmd": "bye",   "pid": 4242 }  // deregister (closing the connection does too)
{ "pattern": "ti", "lines": ["…"], "langs": { … }, "pid": 4242 }  // search
```

A client stays registered exactly while its session connection is open
(process death closes it — that IS the liveness signal); an empty
registry sustained past `FLASH_CJK_SERVER_GRACE_MS` (default 2000)
makes the server unlink its socket and exit. Unknown envelope fields
are ignored, so the modes interoperate.

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
