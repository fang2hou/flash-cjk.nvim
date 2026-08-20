<div align="center">

# flash-cjk.nvim

Jump to any Simplified Chinese, Japanese, or Korean character in Neovim by
typing its pinyin, romaji, or romanization — no IME switching. Built on
[flash.nvim](https://github.com/folke/flash.nvim), forked from
[flash-zh.nvim](https://github.com/rainzm/flash-zh.nvim).

[English](README.md) · [简体中文](README.zh.md) · [日本語](README.ja.md) · [한국어](README.ko.md)

[![Validate](https://github.com/fang2hou/flash-cjk.nvim/actions/workflows/validate.yml/badge.svg)](https://github.com/fang2hou/flash-cjk.nvim/actions/workflows/validate.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](./LICENSE)

</div>

## Why

Typing CJK text to jump to CJK text means fighting your IME mid-motion.
flash-cjk keeps your hands in ASCII: `ni` lands on 日 / に / ニ, `r` hits 日
by pinyin initial, `dkss` hits 안녕 by Dubeolsik keys — while plain letters
still match literally, exactly like flash.nvim.

- In scope: Simplified Chinese pinyin (Xiaohe double-pinyin and initials),
  Japanese romaji (kanji readings plus kana, Hepburn and kunrei-shiki),
  Korean (RR romanization and Dubeolsik key sequences), literal ASCII — all
  simultaneously and independently toggleable
- Out of scope: replacing flash.nvim's own features (treesitter jumps,
  remote, …); IME integration; NFD Korean filenames (see known limitations)
- Status: actively developed

## Install

Requires [flash.nvim](https://github.com/folke/flash.nvim); install with
[lazy.nvim](https://github.com/folke/nvim-lazy):

```lua
return {{
    "fang2hou/flash-cjk.nvim",
    event = "VeryLazy",
    dependencies = "folke/flash.nvim",
    -- Optional Rust accelerator (see "Rust acceleration"): built on
    -- install/update; without cargo the plugin silently uses the vim-regex
    -- path instead. Delete this line to skip the build entirely.
    build = "cargo build --release --manifest-path=rust/Cargo.toml",
    keys = {{
        "s",
        mode = {"n", "x", "o"},
        function()
            require("flash-cjk").jump()
        end,
        desc = "Flash jump (CJK + ASCII)"
    }},
    opts = {
        languages = {
            zhcn = {force_key = "<C-c>"},  -- default: enabled, scheme "xiaohe"
            ja = {force_key = "<C-j>"},         -- default scheme: "roma"
            ko = {force_key = "<C-k>"},
            en = {force_key = "<C-e>"},         -- en has no scheme concept
        },
        mixed_input = true,
    }
}, {
    "folke/flash.nvim",
    event = "VeryLazy",
    opts = {
        highlight = {
            backdrop = false,
            matches = false
        }
    }
}}
```

Not using lazy.nvim? Call `require("flash-cjk").setup({ ... })` yourself with
the same options as `opts` above.

## Use it

Press `s`, type, and jump — same flow as flash.nvim. If your target shows no
label yet, keep typing (like a search); labels use lowercase letters and never
collide with a plausible next input letter for a visible match.

**With an AI coding agent** — paste this into the agent to hand it the repository:

```text
Work in this repository. Read AGENTS.md at the repository root first and follow it.
```

### Forcing a language mid-typing

While typing, press `C-c` / `C-j` / `C-k` / `C-e` to lock matching to
Simplified Chinese / Japanese / Korean / English and recompute instantly:

- `ti` matches both Simplified Chinese (梯/踢…) and Japanese (ち,
  kunrei-shiki); after `C-c` only the Simplified Chinese readings remain —
  ち no longer matches
- Locks stack into the input string: **backspacing over the marker releases
  it**; pressing another lock key switches directly
- Literal English matching is unaffected while locked
- Lock keys are configurable per language (`force_key`, or `false` to
  disable) in the `languages` table — see below

### Language configuration

Each language is configured independently through the `languages` table —
globally via setup, or per jump via a language-code array:

```lua
require("flash-cjk").setup({
    languages = {
        zhcn = {enabled = true, scheme = "xiaohe", force_key = "<C-c>"},
        ja = {enabled = true, scheme = "roma", force_key = "<C-j>"},
        ko = {enabled = true, scheme = "roma", force_key = "<C-k>"},
        en = {enabled = true, force_key = "<C-e>"},  -- no scheme concept
    },
    mixed_input = true,
    priority = { "ja", "zhcn" },  -- label order: ja matches first
})

require("flash-cjk").jump({ "ja", "ko", "en" })  -- this jump: no Simplified Chinese
```

`scheme` accepts `"xiaohe"` for `zhcn` and `"roma"` for `ja`/`ko` (the only
schemes today; more can plug in later); `en` matches literal ASCII, has no
scheme concept and errors if given one. Entries also accept the `true`/`false`
shorthand for `enabled`. `setup` deep-merges: unspecified fields keep their
current value. `jump()` without an array uses the setup-enabled set; a given
array fully decides that jump's set (schemes fall back to each language's
default) and overrides the setup switches.

`priority` orders label assignment by language: matches reachable through
earlier-listed languages receive the earliest labels (a match several
languages can interpret belongs to its highest-priority one), so targets in
your primary language need the fewest label keys. Match sets and jump
semantics are unchanged; unset keeps plain position order.

Single-language users keep one language enabled. Punctuation follows the
language switches: with `zhcn` off, `,` matches 、(Japanese) instead of ，
(fullwidth comma); `。` is shared by zhcn/ja and always matches; `-` → ー
belongs to `ja`.

## Matching by language

### Simplified Chinese (zhcn)

Type the Xiaohe double-pinyin (小鹤双拼) two-key code, or a pinyin initial:
`ni` → 你, `r` → 日. Every character is reachable by its two-key code, and a
single letter matches any character whose pinyin starts with it. The
registered scheme is `"xiaohe"` (see `scheme` under Language configuration) —
the only one today; more can plug in later.

### Japanese (ja)

Type romaji and it matches: `ni` hits 日, `ti` hits ち (kunrei-shiki). Kanji
readings from Unicode Unihan (`kJapanese`/`On`/`Kun`, ~13,000 kanji) match by
romaji prefix up to 3 letters (`n`/`ni`/`nic` all hit 日); kana match all
common romanizations of their syllable (`si`/`shi`, `tu`/`tsu`); youon pairs
match as one unit (`sha` → しゃ/シャ); `-` matches the long-vowel mark ー,
`[`/`]` → 「」『』, `,` → 、, `!` → ！.

### Korean (ko)

Type Dubeolsik (두벌식, the standard Korean two-set keyboard) sequences:
`dkss` → 안녕, `gkrry` → 학교, `dkswek` → 앉다. Or type romanization: RR
romanization (Revised Romanization of Korean, 로마자 표기법) plus common
McCune-Reischauer spellings (`kim`/`gim` → 김), matched per syllable by
prefix. Syllables decompose programmatically into jamo (initial × medial ×
final) — no dictionary data. Tense jamo need Shift on Dubeolsik — use
romanization (`kk`) instead; single-vowel segments work mid-input like
Japanese vowels (`ai` → 아이).

### English (en)

Plain ASCII matches literally, letter for letter, exactly like flash.nvim's
own search — code identifiers stay reachable without any language
interpretation. `en` has no scheme concept. Even with `en` disabled, digits
and uppercase still match literally, and input no enabled language can
interpret (like `n.`) degrades to literal matching.

## Mixed input

A keystroke chain can be read part literally, part as language codes; the
flag decides how freely the two interleave within one interpretation.

- On (default): every mixed interpretation stays reachable — including
  targets where a literal letter follows a language segment.
- Off (`mixed_input = false`): an interpretation, once it enters a
  language segment, can no longer return to literal letters. Literal
  heads keep working; only the reverse shape drops. Long trilingual
  inputs lose 40–60% of their worst-case latency (`nini` falls from 59
  interpretations to 31).
- Recommendation: keep the default unless long inputs visibly lag while
  typing — then turn it off.

Example (zhcn+ja+en): typing `nn` reaches `日n` — 日 is the romaji prefix
`n` (nichi), the trailing `n` is literal, a `[language][literal]` chain
only the default mode keeps. The mirror text `n日` matches in both modes:
literal letters at the head of a chain are always allowed.

## FAQ

- **Will it lag?** Short prefixes (1–2 letters) answer in ~0.5 ms median on
  the built-in vim-regex path (0.1–0.9 ms with one language enabled). The
  heavy case is long trilingual input on that path: up to ~29 ms mean with
  p95 at 138–245 ms on the heaviest mixes. With the native matcher every
  combination stays in a flat 8–25 ms band. See the benchmark tables below.
- **Must I install Rust?** No. The `build =` line builds the optional native
  matcher only when cargo is available; without it the plugin silently uses
  the vim-regex path with identical results (enforced by cross-validation).
- **Does it cost CPU/battery?** The vim-regex path is in-process regex. The
  native matcher spawns one short-lived process per keystroke per visible
  window (~9–12 ms wall time, almost all of it process startup) — the
  footprint is bounded by your typing speed.
- **Sandboxed or restricted environment?** Delete the `build =` line: the
  pure-Lua path needs no compiler and spawns no processes.
- **When do I need the jump array form?** When one specific jump wants a
  different enabled set than setup — temporarily excluding a language
  (`jump({ "ja", "ko", "en" })`), or reaching a language you disabled
  (`jump({ "zhcn", "en" })` still matches Simplified Chinese after
  `zhcn = { enabled = false }` in setup).
- **How do I change or disable a force_key?** In the `languages` table via
  setup: `force_key = "<M-c>"` changes the key, `force_key = false`
  disables that language's lock.

## Rust acceleration (optional)

An optional native matcher builds once and turns on automatically: on the
benchmark below it flattens the worst case — the p95 tail drops 2.3× overall
and up to 10× on Japanese/Simplified Chinese + English mixes — and it keeps
working on patterns whose regex alternation no longer compiles in Vim (E872).
The `build =` line in the lazy spec above handles it; manual build:

```sh
cd rust && cargo build --release
```

Without the binary — or after repeated failures — the plugin transparently
falls back to the pure-Lua vim-regex path with identical behavior, guaranteed
by a strict item-by-item cross-validation suite. Details and measurements:
[rust/README.md](rust/README.md).

## Performance

<p align="center">
  <img
    src="assets/benchmark.svg"
    alt="Benchmark: per-keystroke cost of the vim-regex path vs the native Rust matcher over the persistent server across the full 15-combination language matrix, plus the spawn-to-server before/after"
    width="720"
  />
</p>

Measured on the live per-keystroke paths across the full language-combination
matrix: every single, pair, triple, and the quad drawn from the four language
codes — `zhcn` (Simplified Chinese), `ja` (Japanese), `ko` (Korean), `en`
(English) — 15 combinations × 70 windows = 1,050 generated windows of 20–60
lines. Each row enables only its own languages, samples window text from
those languages, and types 1–6 plausible keystrokes for exactly those
languages (the `en`-only row is pure ASCII words); the seed is deterministic.

**Rust (server)** is the default native path: one request per keystroke to
the persistent matcher server (see below). **Rust (spawn)** is the fallback
transport, one short-lived process per keystroke.

Singles — one language enabled:

| Window mix | vim-regex mean | Rust spawn | Rust server | Ratio | vim-regex p95 | spawn p95 | server p95 |
| ---------- | -------------: | ---------: | ----------: | ----: | ------------: | --------: | ---------: |
| `ja`       |        1.02 ms |    8.45 ms |     0.20 ms |  5.2× |        4.6 ms |   8.77 ms |    0.42 ms |
| `zhcn`     |        0.22 ms |    8.94 ms |     0.15 ms |  1.4× |        0.6 ms |   9.49 ms |    0.21 ms |
| `en`       |        0.09 ms |    8.42 ms |     0.17 ms |  0.5× |        0.1 ms |   8.95 ms |    0.22 ms |
| `ko`       |        0.09 ms |    8.46 ms |     0.15 ms |  0.6× |        0.2 ms |   8.75 ms |    0.21 ms |

Pairs — two languages enabled:

| Window mix    | vim-regex mean | Rust spawn | Rust server | Ratio | vim-regex p95 | spawn p95 | server p95 |
| ------------- | -------------: | ---------: | ----------: | ----: | ------------: | --------: | ---------: |
| `ja` + `en`   |       28.62 ms |    9.87 ms |     1.32 ms | 21.7× |      133.5 ms |  13.76 ms |    4.78 ms |
| `ko` + `en`   |        4.82 ms |   10.57 ms |     2.18 ms |  2.2× |       34.9 ms |  25.43 ms |   16.80 ms |
| `zhcn` + `en` |        4.26 ms |    9.88 ms |     1.29 ms |  3.3× |       42.6 ms |  20.83 ms |   11.85 ms |
| `ja` + `ko`   |        1.10 ms |    8.50 ms |     0.22 ms |  5.1× |        3.9 ms |   8.91 ms |    0.38 ms |
| `zhcn` + `ja` |        1.10 ms |    8.97 ms |     0.23 ms |  4.8× |        4.5 ms |   9.64 ms |    0.42 ms |
| `zhcn` + `ko` |        0.25 ms |    8.91 ms |     0.20 ms |  1.3× |        0.6 ms |   9.41 ms |    0.31 ms |

Triples — three languages enabled:

| Window mix           | vim-regex mean | Rust spawn | Rust server | Ratio | vim-regex p95 | spawn p95 | server p95 |
| -------------------- | -------------: | ---------: | ----------: | ----: | ------------: | --------: | ---------: |
| `zhcn` + `ja` + `en` |       28.77 ms |   11.34 ms |     2.52 ms | 11.4× |      244.9 ms |  24.19 ms |   14.88 ms |
| `ja` + `ko` + `en`   |       20.08 ms |   10.77 ms |     2.18 ms |  9.2× |      125.8 ms |  25.50 ms |   16.01 ms |
| `zhcn` + `ja` + `ko` |        8.83 ms |    9.52 ms |     0.70 ms | 12.6× |       46.3 ms |  10.71 ms |    2.18 ms |
| `zhcn` + `ko` + `en` |        5.47 ms |   10.60 ms |     1.86 ms |  2.9× |       32.2 ms |  19.33 ms |   10.69 ms |

All four languages enabled:

| Window mix                  | vim-regex mean |  Rust spawn | Rust server |    Ratio | vim-regex p95 |    spawn p95 |  server p95 |
| --------------------------- | -------------: | ----------: | ----------: | -------: | ------------: | -----------: | ----------: |
| `zhcn` + `ja` + `ko` + `en` |       16.43 ms |    10.80 ms |     1.97 ms |     8.4× |       89.6 ms |     22.57 ms |    14.09 ms |
| **Overall (1,050 windows)** |    **8.08 ms** | **9.60 ms** | **1.02 ms** | **7.9×** |   **30.1 ms** | **12.83 ms** | **4.27 ms** |

**Methodology.** Each case runs one warmup pass and reports the median of 3
measured passes (`vim.uv.hrtime`); rows are sorted by vim-regex mean within
each group. Ratio is vim-regex mean ÷ Rust server mean — below 1× the
pure-Lua path is faster. The vim-regex timing covers everything a live
keystroke pays: pattern segmentation, alternation build, `vim.regex()`
compile, and the match scan over every visible line. The Rust timings also
cover everything: the server series is one UDS request to the persistent
server (the live path), the spawn series is a full process launch per
keystroke (the fallback transport). 0 of 1,050 patterns hit Vim's NFA
capture-group limit (E872) in this run, but the Rust matcher keeps working
when one does.

**How to read it.** The spawn transport always paid a fixed ~9 ms floor
(~0.9 ms process creation + ~8.2 ms data-table startup per keystroke), which
made the native path lose every light mix. The server pays those once at
startup and then answers in a flat 0.15–2.5 ms band: 13 of 15 categories now
favor Rust, and the two that do not (`ko`/`en` singles) sit at 0.09 vs
0.15–0.17 ms — sub-0.2 ms either way. The tail is where it matters: the
heaviest mixes (`ja`+`en`, `zhcn`+`ja`+`en`) drop from 133–245 ms p95 on
vim-regex to 4.8–14.9 ms, and the overall p95 falls from 30.1 ms to 4.3 ms.
Spawn → server: 9.60 → 1.02 ms mean (9.4×), p50 8.89 → 0.23 ms, p95
12.8 → 4.3 ms.

### Background service (Unix, zero config)

When the binary is present, the plugin transparently keeps one matcher
server per user:

- **Lifecycle**: the server registers a Neovim instance for exactly as
  long as it holds one idle session connection open. Quit Neovim (or
  `kill -9` it) and the registration drops instantly; once no instance
  has been connected for 2 seconds (`FLASH_CJK_SERVER_GRACE_MS`), the
  server removes its socket and exits. The last instance out takes the
  server with it — no polling, no daemon management, no config.
- **Memory**: one resident process at ~12.4 MB RSS, alive only while at
  least one Neovim instance uses it.
- **Automatic fallback**: a transport hiccup (timeout, crash) falls back
  to the per-keystroke spawn transport for that keystroke and revives
  the server asynchronously; repeated failures trip the existing circuit
  breaker down to the vim-regex path. Windows and over-long socket
  paths (the `sun_path` cap) stay on the spawn transport.

**System impact.** Instead of one short-lived ~9–12 ms process per
keystroke per visible window, the cost is a single ~12.4 MB resident
process per user that exists only while you edit, plus a ~0.04 ms Unix
domain socket round trip per keystroke. CPU/battery footprint now tracks
how much you type, not how often you launch processes. The binary is
~1.8 MB, statically carries its data tables, and has no runtime
dependencies. If the binary is missing, fails to build, or fails
repeatedly at runtime, a circuit breaker trips and every keystroke
transparently falls back to the vim-regex path — identical matches,
enforced by the cross-validation suite. Prefer the pure vim-regex path
(i.e. simply don't build the binary) when resident memory is scarce or
process launches are restricted.

Reproduce on your own machine:

```sh
cargo build --release --manifest-path rust/Cargo.toml
nvim -l benches/compare.lua # writes benches/results.json
uv run benches/gen_svg.py   # regenerates assets/benchmark.svg
```

## Known limitations

- macOS stores Korean filenames in NFD (decomposed jamo); both matching
  paths target NFC precomposed syllables, so jumping in oil/netrw filename
  buffers won't match Korean filenames. Normal code and document buffers
  are NFC and unaffected.

## What to read next

| Goal                     | Read                                                                       |
| ------------------------ | -------------------------------------------------------------------------- |
| Develop and validate     | [DEVELOPMENT.md](./DEVELOPMENT.md)                                         |
| Understand the system    | [ARCHITECTURE.md](./ARCHITECTURE.md)                                       |
| Contribute a change      | [CONTRIBUTING.md](./CONTRIBUTING.md)                                       |
| Give it to an agent      | [AGENTS.md](./AGENTS.md)                                                   |
| Native matcher design    | [rust/README.md](./rust/README.md)                                         |
| Read in another language | [简体中文](README.zh.md) · [日本語](README.ja.md) · [한국어](README.ko.md) |

## Environment requirements

- Neovim ≥ 0.10 with [flash.nvim](https://github.com/folke/flash.nvim)
- Optional recent Rust (≥ 1.97, cargo) for the native accelerator —
  everything works without it
- Development toolchain: managed by mise (see [DEVELOPMENT.md](./DEVELOPMENT.md))

## License

MIT — see [LICENSE](./LICENSE). Data derived from the
[Unicode Unihan Database](https://www.unicode.org/) (Unicode License).
Thanks to [flash-zh.nvim](https://github.com/rainzm/flash-zh.nvim) and
[hop-zh-by-flypy](https://github.com/zzhirong/hop-zh-by-flypy).
