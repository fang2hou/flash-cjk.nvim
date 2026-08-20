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

## ⌨️ Usage

Usage is almost identical to flash.nvim: press `s`, then type the input code for the target text. The examples below include the trigger key `s` as part of the full key sequence.

```text
English, a中文，日本語, 한국어. Hello, 你好，こんにちは、안녕하세요.
```

### ASCII

Type `si` (`s` starts flash-cjk and `i` is the query) to match the `i` in `English`, just as with regular flash.nvim.

### Mixed input

Type `sav` to match `a中`: `a` is matched literally as ASCII, while `v` is the Xiaohe double pinyin code prefix for `中`.

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
|      Overall average |   8.23 ms | **0.97 ms** |           8.5× |
|          Overall p95 |   29.1 ms | **4.35 ms** |           6.7× |
| Some heavy scenarios |           |             | **up to ~27×** |

In the most demanding vim-regex scenarios, some three-language combinations average close to 30 ms, with p95 reaching 243 ms. The Rust matcher is primarily intended to reduce input latency in these extreme cases.

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
| `ja`       |        1.22 ms |     0.16 ms |  7.8× |        4.6 ms |    0.40 ms |
| `zhcn`     |        0.20 ms |     0.09 ms |  2.2× |        0.5 ms |    0.14 ms |
| `en`       |        0.08 ms |     0.11 ms | 0.75× |        0.1 ms |    0.14 ms |
| `ko`       |        0.08 ms |     0.10 ms | 0.81× |        0.2 ms |    0.16 ms |

### Two languages

| Window mix    | vim-regex mean | Rust server | Ratio | vim-regex p95 | server p95 |
| ------------- | -------------: | ----------: | ----: | ------------: | ---------: |
| `ja` + `en`   |       29.99 ms |     1.35 ms | 22.2× |      134.1 ms |    5.00 ms |
| `ko` + `en`   |        4.94 ms |     2.13 ms |  2.3× |       35.2 ms |   16.60 ms |
| `zhcn` + `en` |        4.43 ms |     1.23 ms |  3.6× |       44.8 ms |   11.94 ms |
| `ja` + `ko`   |        1.49 ms |     0.18 ms |  8.2× |        4.4 ms |    0.50 ms |
| `zhcn` + `ja` |        1.04 ms |     0.16 ms |  6.4× |        3.6 ms |    0.34 ms |
| `zhcn` + `ko` |        0.24 ms |     0.13 ms |  1.8× |        0.6 ms |    0.25 ms |

### Three languages

| Window mix           | vim-regex mean | Rust server | Ratio | vim-regex p95 | server p95 |
| -------------------- | -------------: | ----------: | ----: | ------------: | ---------: |
| `zhcn` + `ja` + `en` |       29.12 ms |     2.43 ms | 12.0× |      243.4 ms |   14.79 ms |
| `ja` + `ko` + `en`   |       19.48 ms |     2.10 ms |  9.3× |      129.7 ms |   15.47 ms |
| `zhcn` + `ja` + `ko` |        9.07 ms |     0.67 ms | 13.6× |       47.5 ms |    2.40 ms |
| `zhcn` + `ko` + `en` |        5.80 ms |     1.83 ms |  3.2× |       32.9 ms |   10.88 ms |

### Four languages

| Window mix                  | vim-regex mean | Rust server |    Ratio | vim-regex p95 |  server p95 |
| --------------------------- | -------------: | ----------: | -------: | ------------: | ----------: |
| `zhcn` + `ja` + `ko` + `en` |       16.26 ms |     1.90 ms |     8.6× |       95.0 ms |    14.04 ms |
| **Overall (1,050 windows)** |    **8.23 ms** | **0.97 ms** | **8.5×** |   **29.1 ms** | **4.35 ms** |

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
