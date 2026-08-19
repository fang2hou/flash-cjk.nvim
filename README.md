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
        alpha_mixing = true,
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
globally via setup, or per jump via a language-code array or a field-level
override:

```lua
require("flash-cjk").setup({
    languages = {
        zhcn = {enabled = true, scheme = "xiaohe", force_key = "<C-c>"},
        ja = {enabled = true, scheme = "roma", force_key = "<C-j>"},
        ko = {enabled = true, scheme = "roma", force_key = "<C-k>"},
        en = {enabled = true, force_key = "<C-e>"},  -- no scheme concept
    },
    alpha_mixing = true,
    priority = { "ja", "zhcn" },  -- label order: ja matches first
})

require("flash-cjk").jump({ "ja", "ko", "en" })  -- this jump: no Simplified Chinese
require("flash-cjk").jump(nil, { languages = { ja = { force_key = "<C-d>" } } })
require("flash-cjk").jump(nil, { priority = { "ko" } })  -- this jump: label ko matches first
```

`scheme` accepts `"xiaohe"` for `zhcn` and `"roma"` for `ja`/`ko` (the only
schemes today; more can plug in later); `en` matches literal ASCII, has no
scheme concept and errors if given one. Entries also accept the `true`/`false`
shorthand for `enabled`. `setup` deep-merges: unspecified fields keep their
current value. `jump()` without an array uses the setup-enabled set; a given
array fully decides that jump's set (schemes fall back to each language's
default) and overrides the setup switches. The second argument passes flash
options through, with `languages` overriding fields for that jump only —
same shape as setup.

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

## Alpha mixing

An input can mix literal letters with language segments in one chain: `n`
read as the literal letter plus `i` as pinyin still composes `ni` → 你, and
long inputs like `nihao` gain extra mixed-chain interpretations.

- On (default): every mixed-chain variant of your input stays reachable.
- Off (`alpha_mixing = false`): mixed interpretations are dropped — 40–60%
  lower worst-case latency on long trilingual inputs, at the cost of some
  mixed-chain reachability.
- Recommendation: keep the default unless long inputs visibly lag while
  typing — then turn mixing off.

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
- **How do I change or disable a force_key?** In the `languages` table —
  globally via setup or for one jump: `force_key = "<M-c>"` changes the key,
  `force_key = false` disables that language's lock.

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
    alt="Benchmark: per-keystroke cost of the vim-regex path vs the native Rust matcher across the full 15-combination language matrix"
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

Singles — one language enabled:

| Window mix | vim-regex mean | Rust mean | Ratio | vim-regex p95 | Rust p95 |
| ---------- | -------------: | --------: | ----: | ------------: | -------: |
| `ja`       |        0.85 ms |   8.57 ms | 0.10× |       2.74 ms |  9.43 ms |
| `zhcn`     |        0.22 ms |   8.89 ms | 0.03× |       0.51 ms |  9.36 ms |
| `en`       |        0.11 ms |   8.44 ms | 0.01× |       0.18 ms |  9.06 ms |
| `ko`       |        0.11 ms |   8.28 ms | 0.01× |       0.29 ms |  8.54 ms |

Pairs — two languages enabled:

| Window mix    | vim-regex mean | Rust mean | Ratio | vim-regex p95 | Rust p95 |
| ------------- | -------------: | --------: | ----: | ------------: | -------: |
| `ja` + `en`   |        29.6 ms |   9.82 ms |  3.0× |      138.3 ms |  14.2 ms |
| `ko` + `en`   |        4.96 ms |  10.64 ms | 0.47× |       36.4 ms |  24.5 ms |
| `zhcn` + `en` |        4.46 ms |   9.80 ms | 0.46× |       41.5 ms |  20.4 ms |
| `ja` + `ko`   |        1.35 ms |   8.48 ms | 0.16× |       4.19 ms |  8.87 ms |
| `zhcn` + `ja` |        1.03 ms |   8.85 ms | 0.12× |       4.70 ms |  9.34 ms |
| `zhcn` + `ko` |        0.31 ms |   8.98 ms | 0.03× |       0.65 ms |  9.71 ms |

Triples — three languages enabled:

| Window mix           | vim-regex mean | Rust mean | Ratio | vim-regex p95 | Rust p95 |
| -------------------- | -------------: | --------: | ----: | ------------: | -------: |
| `zhcn` + `ja` + `en` |        28.9 ms |  11.17 ms |  2.6× |      245.3 ms |  24.6 ms |
| `ja` + `ko` + `en`   |        20.1 ms |  10.64 ms |  1.9× |      129.7 ms |  24.9 ms |
| `zhcn` + `ja` + `ko` |        8.48 ms |   9.36 ms | 0.91× |       46.8 ms |  11.2 ms |
| `zhcn` + `ko` + `en` |        5.69 ms |  10.69 ms | 0.53× |       32.6 ms |  19.5 ms |

All four languages enabled:

| Window mix                  | vim-regex mean |   Rust mean |     Ratio | vim-regex p95 |    Rust p95 |
| --------------------------- | -------------: | ----------: | --------: | ------------: | ----------: |
| `zhcn` + `ja` + `ko` + `en` |        16.8 ms |    11.44 ms |      1.5× |       95.1 ms |     23.9 ms |
| **Overall (1,050 windows)** |    **8.19 ms** | **9.60 ms** | **0.85×** |   **29.8 ms** | **13.0 ms** |

**Methodology.** Each case runs one warmup pass and reports the median of 3
measured passes (`vim.uv.hrtime`); rows are sorted by vim-regex mean within
each group. Ratio is vim-regex mean ÷ Rust mean — below 1× the pure-Lua path
is faster. The vim-regex timing covers everything a live keystroke pays:
pattern segmentation, alternation build, `vim.regex()` compile, and the
match scan over every visible line. The Rust timing also covers everything:
the `vim.system` process spawn and the JSON round-trip, exactly as the
plugin invokes it. 0 of 1,050 patterns hit Vim's NFA capture-group limit
(E872) in this run — per-mix language flags keep the alternations smaller —
but the Rust matcher keeps working when one does.

**How to read it.** The single-language rows are the per-language baselines:
with one language enabled the alternation stays small and the vim-regex path
answers in 0.1–0.9 ms, while the Rust path always pays its fixed floor
(~1.1 ms process creation + ~8.4 ms binary startup) — the `en`-only row is
almost a pure display of that spawn overhead. The trend to watch is the
tail: adding `en` to `ja` or `zhcn` multiplies the segmentation
interpretations, and the vim-regex cost climbs to ~29 ms mean with p95 at
138–245 ms (visibly laggy while typing), while the Rust path stays in a
flat 8–25 ms band on every mix. Overall the pure-Lua path wins the median
(0.5 ms vs 8.9 ms — short prefixes never wake the binary) and the native
path wins the worst case (p95 13.0 ms vs 29.8 ms, and 5–10× on the heaviest
mixes).

**System impact.** The native matcher spawns one short-lived process per
keystroke per visible window (the benchmark above is single-window). Each
invocation costs ~9–12 ms of wall time, almost all of it process creation
(~1.1 ms) plus the binary's data-table startup (~8.4 ms); the DP matching
itself adds sub-millisecond to a few ms, so the CPU/battery footprint is
bounded by how fast you type — roughly one small process launch per key per
window. The binary is ~1.8 MB, statically carries its data tables, has no
runtime dependencies, and is resident only for the duration of a keystroke.
If the binary is missing, fails to build, or fails repeatedly at runtime, a
circuit breaker trips and every keystroke transparently falls back to the
vim-regex path — identical matches, enforced by the cross-validation suite.
Prefer the pure vim-regex path (i.e. simply don't build the binary) when
process creation is expensive or restricted — sandboxes, hardened
environments — or when you work in one language at a time or mostly type
1–2 letter prefixes, where it is the faster path anyway.

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
