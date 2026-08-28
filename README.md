<div align="center">

# flash-cjk.nvim

Chinese, Japanese, and Korean jump support for [flash.nvim](https://github.com/folke/flash.nvim).

[![Validate](https://github.com/fang2hou/flash-cjk.nvim/actions/workflows/validate.yml/badge.svg)](https://github.com/fang2hou/flash-cjk.nvim/actions/workflows/validate.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](./LICENSE)

**English** · [简体中文](README.zh.md) · [日本語](README.ja.md) · [한국어](README.ko.md)

</div>

[flash.nvim](https://github.com/folke/flash.nvim) is a powerful and flexible Neovim jump plugin, but it is primarily designed for ASCII text, making navigation in CJK text less convenient. **flash-cjk.nvim** extends its matching so you can search and jump to Chinese, Japanese, and Korean text using familiar input methods, while preserving flash.nvim's existing literal ASCII matching. It also includes an optional native Rust matcher that significantly reduces latency with multiple languages, mixed input, and longer queries.

In addition to standard flash.nvim matching, it supports the following input schemes:

- 🇨🇳 **Simplified Chinese**: Xiaohe double pinyin
- 🇯🇵 **Japanese**: romaji
- 🇰🇷 **Korean**: Dubeolsik (두벌식) or romanization

https://github.com/user-attachments/assets/37599dab-b0c6-4d90-8463-cb4706841ac3

## 🚀 Installation

Requires Neovim ≥ 0.10 and [flash.nvim](https://github.com/folke/flash.nvim). The Rust toolchain is optional and is only needed to build the native matcher. Install with [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
	"fang2hou/flash-cjk.nvim",
	event = "VeryLazy",
	dependencies = {
		"folke/flash.nvim",
		keys = { { "s", false } },
	},
	-- Optional: Rust native matcher.
	-- Significantly faster with multiple languages and longer input. Remove this line if you don't need it.
	build = "cargo build --release --manifest-path=rust/Cargo.toml",
	opts = {},
	keys = {
		{
			"s",
			mode = { "n", "x", "o" },
			function()
				require("flash-cjk").jump()
			end,
			desc = "Flash jump (CJK + ASCII)",
		},
	},
}
```

## ⚙️ Configuration

Default configuration:

```lua
{
	languages = {
		zhcn = { enabled = true, filter_key = "<C-c>" },
		ja = { enabled = true, filter_key = "<C-j>" },
		ko = { enabled = true, filter_key = "<C-k>" },
	},
	priority = { "zhcn", "ja", "ko" },
	mixed_input = true,
	char = true,
}
```

### `languages`

Each language can be enabled or disabled for matching. With `enabled = false`, that language is excluded from the search regardless of how `priority` is configured.

`filter_key` lets you **lock the search to a language** while typing, keeping only matches from that language plus literal ASCII. Default keys:

| Language           | Code   | Lock key |
| ------------------ | ------ | -------: |
| Simplified Chinese | `zhcn` |  `<C-c>` |
| Japanese           | `ja`   |  `<C-j>` |
| Korean             | `ko`   |  `<C-k>` |
| ASCII              | `en`   |  `<C-e>` |

`en` is built in; it needs no entry in `languages`.

### `priority`

When multiple languages match at once, `priority = { "zhcn", "ja", "ko" }` determines the order in which matches receive Flash labels: languages listed earlier have higher priority.

### `mixed_input`

Allows a single query to mix input codes from different languages. See Mixed input in the usage examples below.

### `char`

Makes flash.nvim's built-in enhanced char motions (flash's `modes.char`, enabled by default) CJK-aware. A single typed character is matched through the same multi-language engine as `s`-jumps: `fv` jumps to `中` (Xiaohe `v` initial for zhong), while `ft` reaches `中` (Japanese kunrei-shiki `tyuu`) or `梯` (pinyin `ti`). `;`/`,` cycling, counts, and operator-pending behave exactly like flash's native motions. Matching is single-character only — press `s` for full multi-key readings. Set `setup({ char = false })` to restore flash's native ASCII-only behavior.

## ⌨️ Usage

Usage is almost identical to flash.nvim: press `s`, then type the input code for the target text. The examples below include the trigger key `s` as part of the full key sequence.

```text
English, a中文，日本語, 한국어. Hello, 你好，こんにちは、안녕하세요.
```

### ASCII

Type `si` (`s` starts flash-cjk and `i` is the query) to match the `i` in `English`, just as with regular flash.nvim.

### Mixed input

Type `sav` to match `a中`: `a` is matched literally as ASCII, while `v` is the Xiaohe double pinyin code prefix for `中`.

### Char motions

The same engine also powers `f`/`t`/`F`/`T` (flash's enhanced char motions). On the sample line above, `fv` jumps to `中`.

### Multi-language matching

Type `sn`, and the query character `n` matches all of the following at once:

- `n`: ASCII letter
- `中`: Japanese romaji `naka`
- `日`: Japanese romaji `nichi`
- `你`: Xiaohe double pinyin `ni`
- `ん`: Japanese romaji `nn`
- `に`: Japanese romaji `ni`
- `안`: Korean romanization `an`

If there are too many candidates, you can lock the search to a language at any time:

| Key     | Kept matches     |
| ------- | ---------------- |
| `<C-c>` | Chinese + ASCII  |
| `<C-j>` | Japanese + ASCII |
| `<C-k>` | Korean + ASCII   |
| `<C-e>` | ASCII only       |

For example, press `<C-c>` and only `n` and `你` remain. Press Backspace to remove the filter, or press another lock key to switch directly.

## ⚡ Performance

flash-cjk.nvim has two matching paths: Neovim / Vim regex matching and an optional native Rust matcher. Both have low latency with a single language and short input; the difference becomes more noticeable with multiple languages, longer input, and larger amounts of candidate text. In the full four-language combination benchmark:

|                      | vim-regex |        Rust |        Speedup |
| -------------------: | --------: | ----------: | -------------: |
|      Overall average |   9.04 ms | **0.40 ms** |          22.5× |
|          Overall p95 |   33.1 ms | **1.56 ms** |          21.3× |
| Some heavy scenarios |           |             | **up to ~53×** |

In the most demanding vim-regex scenarios, `ja`-containing combinations average over 30 ms per keystroke, with p95 reaching 276 ms. The Rust matcher is primarily intended to reduce input latency in these extreme cases.

### Rust resident server

The Rust matcher automatically starts a persistent server the first time it is used. Subsequent queries reuse that process, avoiding the overhead of creating a new process for every match. Multiple Neovim instances share the same server instead of starting one per editor instance.

<details>
<summary><strong>Full benchmark: vim-regex vs Rust matcher</strong></summary>

<p align="center">
  <img
    src="assets/benchmark.svg"
    alt="Per-keystroke latency of the vim-regex path vs the Rust matcher across the full 15-combination language matrix"
    width="720"
  >
</p>

The benchmark covers four languages: `zhcn` (Simplified Chinese), `ja` (Japanese), `ko` (Korean), and `en` (ASCII), for 15 language combinations × 70 windows = 1,050 generated windows. Each window contains 20–60 lines of text and only includes content for its assigned language combination. Each run enters 1–6 plausible query characters and compares the per-keystroke latency of the actual vim-regex path with the Rust persistent server.

### Single language

| Window mix | vim-regex mean | Rust server | Ratio | vim-regex p95 | server p95 |
| ---------- | -------------: | ----------: | ----: | ------------: | ---------: |
| `ja`       |        1.04 ms |     0.15 ms |  7.2× |        4.4 ms |    0.41 ms |
| `zhcn`     |        0.21 ms |     0.09 ms |  2.4× |        0.5 ms |    0.12 ms |
| `ko`       |        0.08 ms |     0.08 ms |  1.0× |        0.2 ms |    0.11 ms |
| `en`       |        0.07 ms |     0.09 ms |  0.8× |        0.1 ms |    0.13 ms |

### Two languages

| Window mix    | vim-regex mean | Rust server | Ratio | vim-regex p95 | server p95 |
| ------------- | -------------: | ----------: | ----: | ------------: | ---------: |
| `ja` + `en`   |       32.66 ms |     0.62 ms | 52.9× |      144.2 ms |    2.06 ms |
| `ko` + `en`   |        4.88 ms |     0.76 ms |  6.4× |       35.4 ms |    4.45 ms |
| `zhcn` + `en` |        4.44 ms |     0.41 ms | 11.0× |       44.3 ms |    3.32 ms |
| `ja` + `ko`   |        1.55 ms |     0.15 ms | 10.2× |        5.2 ms |    0.32 ms |
| `zhcn` + `ja` |        1.17 ms |     0.16 ms |  7.2× |        6.5 ms |    0.36 ms |
| `zhcn` + `ko` |        0.26 ms |     0.10 ms |  2.5× |        0.6 ms |    0.16 ms |

### Three languages

| Window mix           | vim-regex mean | Rust server | Ratio | vim-regex p95 | server p95 |
| -------------------- | -------------: | ----------: | ----: | ------------: | ---------: |
| `zhcn` + `ja` + `en` |       32.18 ms |     0.98 ms | 32.8× |      276.1 ms |    4.81 ms |
| `ja` + `ko` + `en`   |       22.53 ms |     0.81 ms | 28.0× |      144.5 ms |    4.71 ms |
| `zhcn` + `ja` + `ko` |       10.05 ms |     0.36 ms | 28.0× |       50.4 ms |    1.09 ms |
| `zhcn` + `ko` + `en` |        5.89 ms |     0.57 ms | 10.3× |       36.0 ms |    2.69 ms |

### Four languages

| Window mix                  | vim-regex mean | Rust server |     Ratio | vim-regex p95 |  server p95 |
| --------------------------- | -------------: | ----------: | --------: | ------------: | ----------: |
| `zhcn` + `ja` + `ko` + `en` |       18.67 ms |     0.71 ms |     26.2× |      100.8 ms |     4.30 ms |
| **Overall (1,050 windows)** |    **9.04 ms** | **0.40 ms** | **22.5×** |   **33.1 ms** | **1.56 ms** |

</details>

## 🛠️ Development

### Using an AI coding agent

To hand the repository directly to a coding agent, use:

```text
Work in this repository. Read AGENTS.md at the repository root first and follow it.
```

### Local development

The project uses [mise](https://mise.jdx.dev/) to manage all development dependencies and tasks. After installing mise, run:

```bash
mise install
mise run test
```

`mise run` lists all other tasks (`check`, `e2e`, `codegen`, `format`). See [DEVELOPMENT.md](./DEVELOPMENT.md) for details.

## 📚 Learn More

| Goal                     | Read                                                                       |
| ------------------------ | -------------------------------------------------------------------------- |
| Understand the system    | [ARCHITECTURE.md](./ARCHITECTURE.md)                                       |
| Develop and validate     | [DEVELOPMENT.md](./DEVELOPMENT.md)                                         |
| Contribute               | [CONTRIBUTING.md](./CONTRIBUTING.md)                                       |
| Hand it to an AI agent   | [AGENTS.md](./AGENTS.md)                                                   |
| Native matcher design    | [rust/README.md](./rust/README.md)                                         |
| Read in another language | [简体中文](README.zh.md) · [日本語](README.ja.md) · [한국어](README.ko.md) |

## 📄 License

MIT — see [LICENSE](./LICENSE). Data is derived from the
[Unicode Unihan Database](https://www.unicode.org/) (Unicode License). Thanks to
[flash-zh.nvim](https://github.com/rainzm/flash-zh.nvim) and
[hop-zh-by-flypy](https://github.com/zzhirong/hop-zh-by-flypy).
