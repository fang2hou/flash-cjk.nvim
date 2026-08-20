<div align="center">

# flash-cjk.nvim

为 [flash.nvim](https://github.com/folke/flash.nvim) 提供中文、日语、韩语跳转支持。

[![Validate](https://github.com/fang2hou/flash-cjk.nvim/actions/workflows/validate.yml/badge.svg)](https://github.com/fang2hou/flash-cjk.nvim/actions/workflows/validate.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](./LICENSE)

[English](README.md) · **简体中文** · [日本語](README.ja.md) · [한국어](README.ko.md)

</div>

[flash.nvim](https://github.com/folke/flash.nvim) 是一个强大且灵活的 Neovim 跳转插件，但主要面向 ASCII 文本，因此在 CJK 文本中的使用体验相对有限。**flash-cjk.nvim** 扩展了它的匹配能力：使用熟悉的输入方式搜索并跳转到中文、日语、韩语文本，同时保持原有的 ASCII 字面匹配不变。插件还提供一个可选的 Rust 原生匹配器，可在多语言、混合输入和较长查询等场景下显著降低延迟。

在原生 flash.nvim 的基础上，支持下列输入码的匹配：

- 🇨🇳 **简体中文**：小鹤双拼
- 🇯🇵 **日语**：罗马字
- 🇰🇷 **韩语**：두벌식（Dubeolsik）或罗马字

## 🚀 安装

要求 Neovim ≥ 0.10 和 [flash.nvim](https://github.com/folke/flash.nvim)；Rust toolchain 为可选依赖，仅用于编译原生匹配器。使用 [lazy.nvim](https://github.com/folke/lazy.nvim) 安装：

```lua
{
	"fang2hou/flash-cjk.nvim",
	event = "VeryLazy",
	dependencies = {
		"folke/flash.nvim",
		keys = { { "s", false } },
	},
	-- 可选：Rust 原生匹配器。
	-- 在多语言和长输入场景下性能提升明显；如果不需要，可以删除这一行。
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

## ⚙️ 配置

默认配置：

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

每种语言都可以设置是否参与匹配。设为 `enabled = false` 后，无论 `priority` 如何配置，该语言都不会参与搜索。

`filter_key` 用于在搜索过程中**锁定语言**；锁定后，只保留对应语言和 ASCII 字面匹配的结果。默认快捷键：

| 语言     | 代码   | 锁定键  |
| -------- | ------ | ------- |
| 简体中文 | `zhcn` | `<C-c>` |
| 日语     | `ja`   | `<C-j>` |
| 韩语     | `ko`   | `<C-k>` |
| ASCII    | `en`   | `<C-e>` |

`en` 是内置语言，无需在 `languages` 中额外配置。

### `priority`

当多种语言同时匹配时，`priority = { "zhcn", "ja", "ko" }` 决定匹配结果获得 Flash 标签的优先顺序；越靠前的语言优先级越高。

### `mixed_input`

允许一次查询同时包含不同语言的输入码，见下方使用示例中的混合输入。

## ⌨️ 使用

用法和 flash.nvim 基本一致：按下 `s`，再输入目标文本的输入码即可。下面的示例会把触发键 `s` 一并写入完整按键序列。

```text
English, a中文，日本語, 한국어. Hello, 你好，こんにちは、안녕하세요.
```

### ASCII

输入 `si`（`s` 启动 flash-cjk，`i` 是查询内容），即可匹配 `English` 中的 `i`，行为与普通 flash.nvim 一致。

### 混合输入

输入 `sav` 可以匹配「a中」：`a` 使用 ASCII 字面匹配，`v` 是小鹤双拼中「中」的输入码前缀。

### 多语言匹配

输入 `sn` 后，查询字符 `n` 会同时匹配：

- `n`：ASCII 字母
- `中`：日语罗马字 `naka`
- `日`：日语罗马字 `nichi`
- `你`：小鹤双拼 `ni`
- `ん`：日语罗马字 `nn`
- `に`：日语罗马字 `ni`
- `안`：韩语罗马字 `an`

候选过多时，可以随时锁定语言进行筛选：

| 按键    | 保留的匹配   |
| ------- | ------------ |
| `<C-c>` | 中文 + ASCII |
| `<C-j>` | 日语 + ASCII |
| `<C-k>` | 韩语 + ASCII |
| `<C-e>` | 仅 ASCII     |

例如按下 `<C-c>` 后，只会保留 `n` 和 `你`。可以使用退格删除过滤器，也可以按下另一个锁定键直接切换。

## ⚡ 性能

flash-cjk.nvim 有两条匹配路径：Neovim / Vim regex 匹配，以及可选的 Rust 原生匹配器。在单语言、短输入场景下，两者的延迟都很低；差异主要出现在多语言、长输入和候选文本较多的场景。在完整的四语言组合基准测试中：

|                | vim-regex |        Rust |           加速 |
| -------------- | --------: | ----------: | -------------: |
| 总体平均       |   8.23 ms | **0.97 ms** |           8.5× |
| 总体 p95       |   29.1 ms | **4.35 ms** |           6.7× |
| 部分重负载场景 |           |             | **最高约 27×** |

在匹配开销最高的 vim-regex 场景中，部分三语言组合的平均耗时接近 30 ms，p95 达到 243 ms；Rust 匹配器主要用于降低这些极端情况下的输入延迟。

### Rust 常驻服务

Rust 匹配器首次使用时会自动启动常驻服务，之后的查询会直接复用该进程，从而避免每次匹配都重新创建进程的开销；多个 Neovim 实例共享同一个服务，不会为每个编辑器实例重复启动。

<details>
<summary><strong>完整基准测试：vim-regex vs Rust matcher</strong></summary>

<p align="center">
  <img
    src="assets/benchmark.svg"
    alt="完整 15 组合语言矩阵上 vim-regex 路径与 Rust matcher 的单键延迟"
    width="720"
  >
</p>

测试覆盖四种语言：`zhcn`（简体中文）、`ja`（日语）、`ko`（韩语）、`en`（ASCII），共 15 个语言组合 × 70 个窗口 = 1,050 个生成窗口。每个窗口包含 20–60 行文本，并且只生成与当前语言组合对应的内容。测试过程中输入 1–6 个合理的查询字符，对比真实 vim-regex 路径与 Rust 常驻服务路径的单键延迟。

### 单语言

| 窗口语言 | vim-regex 均值 | Rust server |  比率 | vim-regex p95 | server p95 |
| -------- | -------------: | ----------: | ----: | ------------: | ---------: |
| `ja`     |        1.22 ms |     0.16 ms |  7.8× |        4.6 ms |    0.40 ms |
| `zhcn`   |        0.20 ms |     0.09 ms |  2.2× |        0.5 ms |    0.14 ms |
| `en`     |        0.08 ms |     0.11 ms | 0.75× |        0.1 ms |    0.14 ms |
| `ko`     |        0.08 ms |     0.10 ms | 0.81× |        0.2 ms |    0.16 ms |

### 双语言

| 窗口语言      | vim-regex 均值 | Rust server |  比率 | vim-regex p95 | server p95 |
| ------------- | -------------: | ----------: | ----: | ------------: | ---------: |
| `ja` + `en`   |       29.99 ms |     1.35 ms | 22.2× |      134.1 ms |    5.00 ms |
| `ko` + `en`   |        4.94 ms |     2.13 ms |  2.3× |       35.2 ms |   16.60 ms |
| `zhcn` + `en` |        4.43 ms |     1.23 ms |  3.6× |       44.8 ms |   11.94 ms |
| `ja` + `ko`   |        1.49 ms |     0.18 ms |  8.2× |        4.4 ms |    0.50 ms |
| `zhcn` + `ja` |        1.04 ms |     0.16 ms |  6.4× |        3.6 ms |    0.34 ms |
| `zhcn` + `ko` |        0.24 ms |     0.13 ms |  1.8× |        0.6 ms |    0.25 ms |

### 三语言

| 窗口语言             | vim-regex 均值 | Rust server |  比率 | vim-regex p95 | server p95 |
| -------------------- | -------------: | ----------: | ----: | ------------: | ---------: |
| `zhcn` + `ja` + `en` |       29.12 ms |     2.43 ms | 12.0× |      243.4 ms |   14.79 ms |
| `ja` + `ko` + `en`   |       19.48 ms |     2.10 ms |  9.3× |      129.7 ms |   15.47 ms |
| `zhcn` + `ja` + `ko` |        9.07 ms |     0.67 ms | 13.6× |       47.5 ms |    2.40 ms |
| `zhcn` + `ko` + `en` |        5.80 ms |     1.83 ms |  3.2× |       32.9 ms |   10.88 ms |

### 四语言

| 窗口语言                    | vim-regex 均值 | Rust server |     比率 | vim-regex p95 |  server p95 |
| --------------------------- | -------------: | ----------: | -------: | ------------: | ----------: |
| `zhcn` + `ja` + `ko` + `en` |       16.26 ms |     1.90 ms |     8.6× |       95.0 ms |    14.04 ms |
| **总体（1,050 个窗口）**    |    **8.23 ms** | **0.97 ms** | **8.5×** |   **29.1 ms** | **4.35 ms** |

</details>

## 🛠️ 开发

### 使用 AI Coding Agent

如果希望直接把仓库交给编码代理：

```text
Work in this repository. Read AGENTS.md at the repository root first and follow it.
```

### 本地开发

项目使用 [mise](https://mise.jdx.dev/) 统一管理开发依赖和任务。安装 mise 后运行：

```bash
mise install
mise run test
```

`mise run` 会列出其余所有任务（`check`、`e2e`、`codegen`、`format`），详情参见 [DEVELOPMENT.md](./DEVELOPMENT.md)。

## 📚 延伸阅读

| 目标             | 阅读                                                                   |
| ---------------- | ---------------------------------------------------------------------- |
| 了解系统         | [ARCHITECTURE.md](./ARCHITECTURE.md)                                   |
| 开发与验证       | [DEVELOPMENT.md](./DEVELOPMENT.md)                                     |
| 参与贡献         | [CONTRIBUTING.md](./CONTRIBUTING.md)                                   |
| 交给 AI 代理     | [AGENTS.md](./AGENTS.md)                                               |
| 原生匹配器设计   | [rust/README.md](./rust/README.md)                                     |
| 阅读其他语言版本 | [English](README.md) · [日本語](README.ja.md) · [한국어](README.ko.md) |

## 📄 许可证

MIT——见 [LICENSE](./LICENSE)。数据衍生自
[Unicode Unihan 数据库](https://www.unicode.org/)（Unicode License）。感谢
[flash-zh.nvim](https://github.com/rainzm/flash-zh.nvim) 与
[hop-zh-by-flypy](https://github.com/zzhirong/hop-zh-by-flypy)。
