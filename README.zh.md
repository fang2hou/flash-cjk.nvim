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

https://github.com/user-attachments/assets/37599dab-b0c6-4d90-8463-cb4706841ac3

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
	motions = { char = true },
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

### `motions`

用于集中配置 flash.nvim 自有移动方式的集成。目前是 flash 的 `modes.char`，未来其他 flash 自有的入口（例如 `/` 搜索模式）也会放在这里配置。

#### `char`

让 flash.nvim 内置的增强字符移动（flash 的 `modes.char`，默认开启）也支持 CJK 匹配。输入的单个字符会通过与 `s` 跳转相同的多语言引擎匹配：`fv` 可以跳到「中」（小鹤双拼中 zhong 的声母 `v`），`ft` 则能到达「中」（日语训令式罗马字 `tyuu`）或「梯」（拼音 `ti`）。`;`/`,` 循环、计数和 operator-pending 行为与 flash 原生移动完全一致。匹配只支持单个字符——需要完整的多键输入码时请按 `s`。设置 `setup({ motions = { char = false } })` 即可恢复 flash 原生的纯 ASCII 行为。

## ⌨️ 使用

用法和 flash.nvim 基本一致：按下 `s`，再输入目标文本的输入码即可。下面的示例会把触发键 `s` 一并写入完整按键序列。

```text
English, a中文，日本語, 한국어. Hello, 你好，こんにちは、안녕하세요.
```

### ASCII

输入 `si`（`s` 启动 flash-cjk，`i` 是查询内容），即可匹配 `English` 中的 `i`，行为与普通 flash.nvim 一致。

### 混合输入

输入 `sav` 可以匹配「a中」：`a` 使用 ASCII 字面匹配，`v` 是小鹤双拼中「中」的输入码前缀。

### 字符移动

同样的引擎也作用于 `f`/`t`/`F`/`T`（flash 的增强字符移动）。在上面这行示例中，`fv` 会跳到「中」。

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
| 总体平均       |   9.04 ms | **0.40 ms** |          22.5× |
| 总体 p95       |   33.1 ms | **1.56 ms** |          21.3× |
| 部分重负载场景 |           |             | **最高约 53×** |

在匹配开销最高的 vim-regex 场景中，含 `ja` 的组合平均耗时超过 30 ms，p95 达到 276 ms；Rust 匹配器主要用于降低这些极端情况下的输入延迟。

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

| 窗口语言 | vim-regex 均值 | Rust server | 比率 | vim-regex p95 | server p95 |
| -------- | -------------: | ----------: | ---: | ------------: | ---------: |
| `ja`     |        1.04 ms |     0.15 ms | 7.2× |        4.4 ms |    0.41 ms |
| `zhcn`   |        0.21 ms |     0.09 ms | 2.4× |        0.5 ms |    0.12 ms |
| `ko`     |        0.08 ms |     0.08 ms | 1.0× |        0.2 ms |    0.11 ms |
| `en`     |        0.07 ms |     0.09 ms | 0.8× |        0.1 ms |    0.13 ms |

### 双语言

| 窗口语言      | vim-regex 均值 | Rust server |  比率 | vim-regex p95 | server p95 |
| ------------- | -------------: | ----------: | ----: | ------------: | ---------: |
| `ja` + `en`   |       32.66 ms |     0.62 ms | 52.9× |      144.2 ms |    2.06 ms |
| `ko` + `en`   |        4.88 ms |     0.76 ms |  6.4× |       35.4 ms |    4.45 ms |
| `zhcn` + `en` |        4.44 ms |     0.41 ms | 11.0× |       44.3 ms |    3.32 ms |
| `ja` + `ko`   |        1.55 ms |     0.15 ms | 10.2× |        5.2 ms |    0.32 ms |
| `zhcn` + `ja` |        1.17 ms |     0.16 ms |  7.2× |        6.5 ms |    0.36 ms |
| `zhcn` + `ko` |        0.26 ms |     0.10 ms |  2.5× |        0.6 ms |    0.16 ms |

### 三语言

| 窗口语言             | vim-regex 均值 | Rust server |  比率 | vim-regex p95 | server p95 |
| -------------------- | -------------: | ----------: | ----: | ------------: | ---------: |
| `zhcn` + `ja` + `en` |       32.18 ms |     0.98 ms | 32.8× |      276.1 ms |    4.81 ms |
| `ja` + `ko` + `en`   |       22.53 ms |     0.81 ms | 28.0× |      144.5 ms |    4.71 ms |
| `zhcn` + `ja` + `ko` |       10.05 ms |     0.36 ms | 28.0× |       50.4 ms |    1.09 ms |
| `zhcn` + `ko` + `en` |        5.89 ms |     0.57 ms | 10.3× |       36.0 ms |    2.69 ms |

### 四语言

| 窗口语言                    | vim-regex 均值 | Rust server |      比率 | vim-regex p95 |  server p95 |
| --------------------------- | -------------: | ----------: | --------: | ------------: | ----------: |
| `zhcn` + `ja` + `ko` + `en` |       18.67 ms |     0.71 ms |     26.2× |      100.8 ms |     4.30 ms |
| **总体（1,050 个窗口）**    |    **9.04 ms** | **0.40 ms** | **22.5×** |   **33.1 ms** | **1.56 ms** |

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
