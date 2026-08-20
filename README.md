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

Typing CJK text to jump to CJK text means fighting your IME mid-motion.
flash-cjk keeps your hands in ASCII: `ni` lands on 你 / 日 / に / ニ, `r`
hits 日 by pinyin initial, `dkss` hits 안녕 by Dubeolsik keys — while plain
letters still match literally, exactly like flash.nvim.

- In scope: Simplified Chinese pinyin (Xiaohe double-pinyin and initials),
  Japanese romaji (kanji readings plus kana, Hepburn and kunrei-shiki),
  Korean (RR romanization and Dubeolsik key sequences), literal ASCII — all
  simultaneously and independently toggleable
- Out of scope: replacing flash.nvim's own features (treesitter jumps,
  remote, …); IME integration; NFD Korean filenames (see known limitations
  under Features)
- Status: actively developed

## 🚀 Usage

Requires [flash.nvim](https://github.com/folke/flash.nvim) and Neovim ≥ 0.10.
Install with [lazy.nvim](https://github.com/folke/nvim-lazy):

```lua
return {{
    "fang2hou/flash-cjk.nvim",
    event = "VeryLazy",
    dependencies = "folke/flash.nvim",
    -- Optional Rust accelerator (see "⚡ Performance"): built on
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

Press `s`, type, and jump — same flow as flash.nvim. If your target shows no
label yet, keep typing (like a search); labels use lowercase letters and never
collide with a plausible next input letter for a visible match.

**With an AI coding agent** — paste this into the agent to hand it the repository:

```text
Work in this repository. Read AGENTS.md at the repository root first and follow it.
```

**Developing or benchmarking the plugin** requires [mise](https://mise.jdx.dev/)
on macOS or Linux:

```bash
mise install
mise run test
```

`mise run` lists every other task (`check`, `e2e`, `codegen`, `format`); see
[DEVELOPMENT.md](./DEVELOPMENT.md).

<details>
<summary>Rust accelerator: when you need it, when you don't</summary>

The `build =` line above builds the optional native matcher only when cargo
is available; manual build: `cd rust && cargo build --release`. You do not
need Rust: without the binary the plugin silently uses the vim-regex path
with identical results (enforced by cross-validation). In sandboxed or
restricted environments, delete the `build =` line — the pure-Lua path needs
no compiler and spawns no processes.

</details>

## 💡 Concepts

- **Interpretations** — every keystroke chain is segmented into literal
  letters and language codes (pinyin, romaji, romanization); each plausible
  reading of the same input stays reachable at once. `ni` matches both
  Simplified Chinese (你) and Japanese (日 / に / ニ).
- **Language lock** — while typing, `C-c` / `C-j` / `C-k` / `C-e` lock
  matching to Simplified Chinese / Japanese / Korean / English and recompute
  instantly: after `C-c`, only the Simplified Chinese readings remain — ち
  no longer matches. Locks stack into the input string, so **backspacing
  over the marker releases it**; pressing another lock key switches
  directly. Lock keys are configurable per language (`force_key`, or
  `false` to disable).
- **Mixed input** — a keystroke chain can be read part literally, part as
  language codes. Typing `nn` reaches `日n` (romaji `n` + literal `n`); the
  mirror text `n日` matches in every mode because literal heads are always
  allowed. Turning `mixed_input = false` drops only the reverse shape
  (language-then-literal) and cuts worst-case latency on long trilingual
  inputs by 40–60% — keep the default unless long inputs visibly lag.
- **Per-jump language set** — each language is configured independently
  through the `languages` table (globally via `setup`, or per jump:
  `jump({ "ja", "ko", "en" })` matches no Simplified Chinese for that one
  jump). `setup` deep-merges; the `true`/`false` shorthand toggles
  `enabled`. Punctuation follows the switches: with `zhcn` off, `,` matches
  、(Japanese) instead of ，(fullwidth comma).

## ✨ Features

- **Simplified Chinese (`zhcn`)** — type the Xiaohe double-pinyin
  (小鹤双拼) two-key code, or a pinyin initial: `ni` → 你, `r` → 日. Every
  character is reachable by its two-key code; a single letter matches any
  character whose pinyin starts with it. Scheme: `"xiaohe"` (the only one
  today; more can plug in later).
- **Japanese (`ja`)** — romaji matching: `ni` hits 日, `ti` hits ち
  (kunrei-shiki). Kanji readings from Unicode Unihan (~13,000 kanji) match
  by romaji prefix up to 3 letters (`n`/`ni`/`nic` all hit 日); kana match
  all common romanizations of their syllable (`si`/`shi`, `tu`/`tsu`);
  youon pairs match as one unit (`sha` → しゃ/シャ); `-` matches ー,
  `[`/`]` → 「」『』, `,` → 、, `!` → ！.
- **Korean (`ko`)** — Dubeolsik (두벌식, the standard two-set keyboard)
  sequences: `dks` → 안, `gkrry` → 학교, `dkswek` → 앉다. Or romanization:
  RR (Revised Romanization of Korean, 로마자 표기법) plus common
  McCune-Reischauer spellings (`kim`/`gim` → 김), matched per syllable by
  prefix. Syllables decompose programmatically into jamo — no dictionary
  data. Tense jamo need Shift on Dubeolsik — use romanization (`kk`)
  instead; single-vowel segments work mid-input like Japanese vowels
  (`ai` → 아이).
- **English (`en`)** — plain ASCII matches literally, letter for letter,
  exactly like flash.nvim's own search: code identifiers stay reachable
  without any language interpretation. Even with `en` disabled, digits and
  uppercase still match literally, and input no enabled language can
  interpret (like `n.`) degrades to literal matching.
- **Priority labels** — `priority = { "ja", "zhcn" }` orders label
  assignment: matches reachable through earlier-listed languages receive
  the earliest labels, so targets in your primary language need the fewest
  label keys. Match sets and jump semantics are unchanged; unset keeps
  plain position order.

Known limitations: macOS stores Korean filenames in NFD (decomposed jamo);
both matching paths target NFC precomposed syllables, so jumping in
oil/netrw filename buffers won't match Korean filenames. Normal code and
document buffers are NFC and unaffected.

## ⚡ Performance

Short prefixes (1–2 letters) answer in ~0.5 ms median on the built-in
vim-regex path (0.1–0.9 ms with one language enabled). The heavy case is
long trilingual input on that path: up to ~30 ms mean with p95 at 134–243 ms
on the heaviest mixes. The optional native matcher flattens the worst case —
mean drops 8.5× overall, the p95 tail 6.7× (up to 27× on the heaviest mixes)
— and keeps working on patterns whose regex alternation no longer compiles
in Vim (E872). It turns on automatically once built.

<p align="center">
  <img
    src="assets/benchmark.svg"
    alt="Benchmark: per-keystroke cost of the vim-regex path vs the native Rust matcher over the persistent server across the full 15-combination language matrix"
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

**Rust (server)** is the native path live keystrokes use: one request per
keystroke to the persistent matcher server (see below).

Singles — one language enabled:

| Window mix | vim-regex mean | Rust server | Ratio | vim-regex p95 | server p95 |
| ---------- | -------------: | ----------: | ----: | ------------: | ---------: |
| `ja`       |        1.22 ms |     0.16 ms |  7.8× |        4.6 ms |    0.40 ms |
| `zhcn`     |        0.20 ms |     0.09 ms |  2.2× |        0.5 ms |    0.14 ms |
| `en`       |        0.08 ms |     0.11 ms | 0.75× |        0.1 ms |    0.14 ms |
| `ko`       |        0.08 ms |     0.10 ms | 0.81× |        0.2 ms |    0.16 ms |

Pairs — two languages enabled:

| Window mix    | vim-regex mean | Rust server | Ratio | vim-regex p95 | server p95 |
| ------------- | -------------: | ----------: | ----: | ------------: | ---------: |
| `ja` + `en`   |       29.99 ms |     1.35 ms | 22.2× |      134.1 ms |    5.00 ms |
| `ko` + `en`   |        4.94 ms |     2.13 ms |  2.3× |       35.2 ms |   16.60 ms |
| `zhcn` + `en` |        4.43 ms |     1.23 ms |  3.6× |       44.8 ms |   11.94 ms |
| `ja` + `ko`   |        1.49 ms |     0.18 ms |  8.2× |        4.4 ms |    0.50 ms |
| `zhcn` + `ja` |        1.04 ms |     0.16 ms |  6.4× |        3.6 ms |    0.34 ms |
| `zhcn` + `ko` |        0.24 ms |     0.13 ms |  1.8× |        0.6 ms |    0.25 ms |

Triples — three languages enabled:

| Window mix           | vim-regex mean | Rust server | Ratio | vim-regex p95 | server p95 |
| -------------------- | -------------: | ----------: | ----: | ------------: | ---------: |
| `zhcn` + `ja` + `en` |       29.12 ms |     2.43 ms | 12.0× |      243.4 ms |   14.79 ms |
| `ja` + `ko` + `en`   |       19.48 ms |     2.10 ms |  9.3× |      129.7 ms |   15.47 ms |
| `zhcn` + `ja` + `ko` |        9.07 ms |     0.67 ms | 13.6× |       47.5 ms |    2.40 ms |
| `zhcn` + `ko` + `en` |        5.80 ms |     1.83 ms |  3.2× |       32.9 ms |   10.88 ms |

All four languages enabled:

| Window mix                  | vim-regex mean | Rust server |    Ratio | vim-regex p95 |  server p95 |
| --------------------------- | -------------: | ----------: | -------: | ------------: | ----------: |
| `zhcn` + `ja` + `ko` + `en` |       16.26 ms |     1.90 ms |     8.6× |       95.0 ms |    14.04 ms |
| **Overall (1,050 windows)** |    **8.23 ms** | **0.97 ms** | **8.5×** |   **29.1 ms** | **4.35 ms** |

**Methodology.** Each case runs one warmup pass and reports the median of 3
measured passes (`vim.uv.hrtime`); rows are sorted by vim-regex mean within
each group. Ratio is vim-regex mean ÷ Rust server mean — below 1× the
pure-Lua path is faster. The vim-regex timing covers everything a live
keystroke pays: pattern segmentation, alternation build, `vim.regex()`
compile, and the match scan over every visible line. The Rust timing is
one UDS request to the persistent server — the exact transport live
keystrokes use. 0 of 1,050 patterns hit Vim's NFA capture-group limit
(E872) in this run, but the Rust matcher keeps working when one does.

**How to read it.** The server pays process creation and data-table
startup once at its own start, then answers in a flat 0.09–2.5 ms band:
13 of 15 categories favor Rust, and the two that do not (`en`/`ko`
singles) sit at 0.08 vs 0.10–0.11 ms — sub-0.2 ms either way. The tail
is where it matters: the heaviest mixes (`ja`+`en`,
`zhcn`+`ja`+`en`) drop from 134–243 ms p95 on vim-regex to 5.0–14.8 ms,
and the overall p95 falls from 29.1 ms to 4.4 ms.

<details>
<summary>Background service (Unix, zero config)</summary>

When the binary is present, the plugin transparently keeps one matcher
server per user:

- **Lifecycle**: the server registers a Neovim instance for exactly as
  long as it holds one idle session connection open. Quit Neovim (or
  `kill -9` it) and the registration drops instantly; once no instance
  has been connected for 2 seconds (`FLASH_CJK_SERVER_GRACE_MS`), the
  server removes its socket and exits. The last instance out takes the
  server with it — no polling, no daemon management, no config.
- **Memory**: one resident process at ~12.4 MB RSS, alive only while at
  least one Neovim instance uses it, plus a ~0.04 ms Unix domain socket
  round trip per keystroke. CPU/battery footprint tracks how much you
  type, not how often you launch processes.
- **Automatic fallback**: a transport hiccup (timeout, crash) falls back
  to the per-keystroke spawn transport for that keystroke and revives
  the server asynchronously; repeated failures trip the circuit breaker
  down to the vim-regex path. Windows and over-long socket paths (the
  `sun_path` cap) stay on the spawn transport.

The binary is ~1.8 MB, statically carries its data tables, and has no
runtime dependencies. Prefer the pure vim-regex path (i.e. simply don't
build the binary) when resident memory is scarce or process launches are
restricted.

</details>

Reproduce on your own machine:

```sh
cargo build --release --manifest-path rust/Cargo.toml
nvim -l benches/compare.lua # writes benches/results.json
uv run benches/gen_svg.py   # regenerates assets/benchmark.svg
```

## 📚 Learn More

| Goal                     | Read                                                                       |
| ------------------------ | -------------------------------------------------------------------------- |
| Understand the system    | [ARCHITECTURE.md](./ARCHITECTURE.md)                                       |
| Develop and validate     | [DEVELOPMENT.md](./DEVELOPMENT.md)                                         |
| Contribute a change      | [CONTRIBUTING.md](./CONTRIBUTING.md)                                       |
| Give it to an agent      | [AGENTS.md](./AGENTS.md)                                                   |
| Native matcher design    | [rust/README.md](./rust/README.md)                                         |
| Read in another language | [简体中文](README.zh.md) · [日本語](README.ja.md) · [한국어](README.ko.md) |

## 📄 License

MIT — see [LICENSE](./LICENSE). Data derived from the
[Unicode Unihan Database](https://www.unicode.org/) (Unicode License).
Thanks to [flash-zh.nvim](https://github.com/rainzm/flash-zh.nvim) and
[hop-zh-by-flypy](https://github.com/zzhirong/hop-zh-by-flypy).
