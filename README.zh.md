<div align="center">

# flash-cjk.nvim

在 Neovim 中输入拼音、罗马音（Romaji）或罗马字，即可跳转到任意简体中文、
日语或韩语字符——无需切换输入法。基于
[flash.nvim](https://github.com/folke/flash.nvim) 构建，fork 自
[flash-zh.nvim](https://github.com/rainzm/flash-zh.nvim)。

[English](README.md) · [简体中文](README.zh.md) · [日本語](README.ja.md) · [한국어](README.ko.md)

[![Validate](https://github.com/fang2hou/flash-cjk.nvim/actions/workflows/validate.yml/badge.svg)](https://github.com/fang2hou/flash-cjk.nvim/actions/workflows/validate.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](./LICENSE)

</div>

为了跳转到 CJK 文本而再去输入 CJK 文本，意味着操作中途还得与输入法缠斗。
flash-cjk 让你的双手始终停留在 ASCII 上：`ni` 落在 你 / 日 / に / ニ，`r`
按拼音首字母命中 日，`dkss` 按两拼式键盘（두벌식）键位命中
안녕——同时普通字母依然按字面匹配，与 flash.nvim 的行为完全一致。

- 覆盖范围：简体中文拼音（小鹤双拼与拼音首字母）、日语罗马音（Romaji，
  汉字读音与假名，黑本式与训令式）、韩语（RR 罗马字与两拼式键盘键序）、
  ASCII 字面匹配——全部同时生效，且可各自独立开关
- 不在范围内：取代 flash.nvim 自带功能（treesitter 跳转、remote
  等）；输入法集成；NFD 形式的韩文文件名（见「功能特性」下的已知限制）
- 状态：活跃开发中

## 🚀 使用

需要 [flash.nvim](https://github.com/folke/flash.nvim) 和 Neovim ≥ 0.10，
使用 [lazy.nvim](https://github.com/folke/nvim-lazy) 安装：

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

不用 lazy.nvim？自行调用 `require("flash-cjk").setup({ ... })`，选项与上面的
`opts` 相同。

按下 `s`，输入，跳转——流程与 flash.nvim 一致。如果目标上还没出现标签，
继续输入即可（就像搜索一样）；标签使用小写字母，且绝不会与可见匹配项可能
出现的下一个输入字母冲突。

**配合 AI 编程代理**——把下面这段话粘贴给代理，把仓库交给它：

```text
Work in this repository. Read AGENTS.md at the repository root first and follow it.
```

**开发或对插件做基准测试**需要 macOS 或 Linux 上的
[mise](https://mise.jdx.dev/)：

```bash
mise install
mise run test
```

`mise run` 会列出其余全部任务（`check`、`e2e`、`codegen`、`format`）；参见
[DEVELOPMENT.md](./DEVELOPMENT.md)。

<details>
<summary>Rust 加速器：什么时候需要，什么时候不需要</summary>

上面的 `build =` 行只在有 cargo 时才构建可选的原生匹配器；手动构建：
`cd rust && cargo build --release`。你不需要 Rust：没有该二进制时，插件
会静默改走 vim-regex 路径，结果完全一致（由交叉验证保证）。在沙箱或
受限环境中，删掉 `build =` 行即可——纯 Lua 路径不需要编译器，也不启动
任何进程。

</details>

## 💡 核心概念

- **解释**——每条按键链都会被切分为字面字母与语言码（拼音、罗马音、
  罗马字）；同一输入的每种合理解读同时保持可达。`ni` 同时匹配简体中文
  （你）与日语（日 / に / ニ）。
- **语言锁定**——输入过程中，`C-c` / `C-j` / `C-k` / `C-e` 将匹配锁定为
  简体中文 / 日语 / 韩语 / 英语，并立即重新计算：按下 `C-c` 后只剩简体
  中文读音——ち 不再匹配。锁定会叠加进输入串，因此**退格删过标记即解除
  锁定**；按其他锁定键则直接切换。锁定按键按语言配置（`force_key`，设为
  `false` 可禁用）。
- **混合输入**——一条按键链可以一部分按字面、一部分按语言码解读。输入
  `nn` 可到达 `日n`（罗马音 `n` + 字面 `n`）；镜像文本 `n日` 在任何模式下
  都能命中，因为字面开头永远允许。将 `mixed_input` 设为 `false` 只丢弃
  反向形态（先语言段后字面），并让三语长输入的最坏情况延迟降低
  40–60%——除非长输入明显卡顿，否则保持默认。
- **按次跳转的语言集**——每种语言都通过 `languages` 表独立配置（全局经
  `setup`，或按次跳转：`jump({ "ja", "ko", "en" })` 在该次跳转中不匹配
  简体中文）。`setup` 深合并；`true`/`false` 简写等价于开关 `enabled`。
  标点跟随语言开关：关闭 `zhcn` 后，`,` 匹配 、（日文）而非 ，（全角
  逗号）。

## ✨ 功能特性

- **简体中文（`zhcn`）**——输入小鹤双拼（Xiaohe double-pinyin）两键
  编码，或拼音首字母：`ni` → 你，`r` → 日。每个汉字都能用两键编码到达；
  单个字母可命中所有拼音以该字母开头的汉字。方案：`"xiaohe"`（目前
  唯一，今后可接入更多）。
- **日语（`ja`）**——罗马音匹配：`ni` 命中 日，`ti` 命中 ち（训令式）。
  汉字读音取自 Unicode Unihan（约 13,000 个汉字），按罗马音前缀匹配，
  前缀最长 3 个字母（`n`/`ni`/`nic` 均命中 日）；假名匹配其音节的所有
  常见罗马音拼法（`si`/`shi`、`tu`/`tsu`）；拗音成对作为一个整体匹配
  （`sha` → しゃ/シャ）；`-` 匹配 ー，`[`/`]` → 「」『』，`,` → 、，
  `!` → ！。
- **韩语（`ko`）**——两拼式（두벌식，Dubeolsik，韩语标准键盘）键序：
  `dks` → 안、`gkrry` → 학교、`dkswek` → 앉다。也可输入罗马字：RR
  （Revised Romanization of Korean，로마자 표기법）以及常见的
  McCune-Reischauer 拼法（`kim`/`gim` → 김），逐音节按前缀匹配。音节由
  程序规则分解为韩文字母（jamo）——无需词典数据。紧音字母在两拼式键盘
  上需按 Shift——改用罗马字（`kk`）即可；单元音片段可像日语元音一样
  出现在输入中间（`ai` → 아이）。
- **英语（`en`）**——普通 ASCII 按字面逐字母匹配，与 flash.nvim 自带
  搜索完全一致：代码标识符无需任何语言解释即可到达。即使关闭 `en`，数字
  与大写字母仍按字面匹配；所有已启用语言都无法解读的输入（如 `n.`）会
  退化为字面匹配。
- **标签优先级**——`priority = { "ja", "zhcn" }` 决定标签分配顺序：排在
  前面的语言可达的匹配先拿到最早的标签，因此主力语言的目标所需的标签键
  最少。匹配集与跳转语义不变；未设置时保持普通的位置顺序。

已知限制：macOS 以 NFD（分解的韩文字母序列）存储韩文文件名；两条匹配
路径都针对 NFC 预组合音节，因此在 oil/netrw 的文件名缓冲区中跳转时无法
匹配韩文文件名。普通代码与文档缓冲区为 NFC，不受影响。

## ⚡ 性能

短前缀（1–2 个字母）在内置 vim-regex 路径上中位数约 0.5 ms 即可应答
（单语言启用时 0.1–0.9 ms）。重负载场景是该路径上的三语长输入：最重的
组合平均可达约 30 ms、p95 达 134–243 ms。可选的原生匹配器压平了最坏
情况——均值总体降低 8.5×，p95 尾部降低 6.7×（最重组合最高 27×）——并且
对正则选择分支已超出 Vim 编译上限（E872）的模式依然可用。构建完成后
自动启用。

<p align="center">
  <img
    src="assets/benchmark.svg"
    alt="基准测试：完整 15 组合语言矩阵上 vim-regex 路径与常驻服务上的原生 Rust 匹配器的单键开销"
    width="720"
  />
</p>

在完整语言组合矩阵上实测两条真实按键路径：四种语言代码——`zhcn`（简体中文）、`ja`（日语）、`ko`（韩语）、`en`（英语）——的全部单选、双选、三选与四选组合，共 15 组 × 70 个窗口 = 1,050 个 20–60 行的生成窗口。每一行只启用本行语言、从这些语言采样窗口文本、并键入 1–6 个对这些语言合理的按键（`en` 单选行为纯 ASCII 单词）；种子固定可复现。

**Rust（server）**是原生路径，真实按键即走此路：每次按键向常驻匹配服务发送一个请求（见下文）。

单语言——只启用一种语言：

| 窗口语言 | vim-regex 均值 | Rust server |  比率 | vim-regex p95 | server p95 |
| -------- | -------------: | ----------: | ----: | ------------: | ---------: |
| `ja`     |        1.22 ms |     0.16 ms |  7.8× |        4.6 ms |    0.40 ms |
| `zhcn`   |        0.20 ms |     0.09 ms |  2.2× |        0.5 ms |    0.14 ms |
| `en`     |        0.08 ms |     0.11 ms | 0.75× |        0.1 ms |    0.14 ms |
| `ko`     |        0.08 ms |     0.10 ms | 0.81× |        0.2 ms |    0.16 ms |

双语言——启用两种语言：

| 窗口语言      | vim-regex 均值 | Rust server |  比率 | vim-regex p95 | server p95 |
| ------------- | -------------: | ----------: | ----: | ------------: | ---------: |
| `ja` + `en`   |       29.99 ms |     1.35 ms | 22.2× |      134.1 ms |    5.00 ms |
| `ko` + `en`   |        4.94 ms |     2.13 ms |  2.3× |       35.2 ms |   16.60 ms |
| `zhcn` + `en` |        4.43 ms |     1.23 ms |  3.6× |       44.8 ms |   11.94 ms |
| `ja` + `ko`   |        1.49 ms |     0.18 ms |  8.2× |        4.4 ms |    0.50 ms |
| `zhcn` + `ja` |        1.04 ms |     0.16 ms |  6.4× |        3.6 ms |    0.34 ms |
| `zhcn` + `ko` |        0.24 ms |     0.13 ms |  1.8× |        0.6 ms |    0.25 ms |

三语言——启用三种语言：

| 窗口语言             | vim-regex 均值 | Rust server |  比率 | vim-regex p95 | server p95 |
| -------------------- | -------------: | ----------: | ----: | ------------: | ---------: |
| `zhcn` + `ja` + `en` |       29.12 ms |     2.43 ms | 12.0× |      243.4 ms |   14.79 ms |
| `ja` + `ko` + `en`   |       19.48 ms |     2.10 ms |  9.3× |      129.7 ms |   15.47 ms |
| `zhcn` + `ja` + `ko` |        9.07 ms |     0.67 ms | 13.6× |       47.5 ms |    2.40 ms |
| `zhcn` + `ko` + `en` |        5.80 ms |     1.83 ms |  3.2× |       32.9 ms |   10.88 ms |

四种语言全部启用：

| 窗口语言                    | vim-regex 均值 | Rust server |     比率 | vim-regex p95 |  server p95 |
| --------------------------- | -------------: | ----------: | -------: | ------------: | ----------: |
| `zhcn` + `ja` + `ko` + `en` |       16.26 ms |     1.90 ms |     8.6× |       95.0 ms |    14.04 ms |
| **总体（1,050 个窗口）**    |    **8.23 ms** | **0.97 ms** | **8.5×** |   **29.1 ms** | **4.35 ms** |

**方法。** 每个用例先跑一次预热，再取 3 次实测的中位数（`vim.uv.hrtime`）；组内行按 vim-regex 均值排序。比率为 vim-regex 均值 ÷ Rust server 均值——低于 1× 表示纯 Lua 路径更快。vim-regex 计时覆盖真实按键的全部开销：模式切分、备选分支构建、`vim.regex()` 编译、以及每个可见行的匹配扫描。Rust 计时是向常驻服务发送的一个 UDS 请求——与真实按键完全相同的传输。本轮 0/1,050 个模式触发 Vim 的 NFA 捕获组上限（E872），但即使触发，Rust 匹配器仍可继续工作。

**如何解读。** 常驻服务只在自身启动时支付一次进程创建与数据表构建，之后在 0.09–2.5 ms 的平坦区间内应答：15 个类别中有 13 个 Rust 占优，其余两个（`en`/`ko` 单选）为 0.08 对 0.10–0.11 ms——双方都在 0.2 ms 以内。更重要的是尾部：最重的组合（`ja`+`en`、`zhcn`+`ja`+`en`）的 p95 从 vim-regex 的 134–243 ms 降到 5.0–14.8 ms，总体 p95 从 29.1 ms 降到 4.4 ms。

<details>
<summary>后台服务（Unix，零配置）</summary>

二进制存在时，插件会透明地为每个用户维护一个匹配服务：

- **生命周期**：一个 Neovim 实例持有空闲会话连接期间即视为注册。退出
  Neovim（或被 `kill -9`）会立即注销；当没有任何实例连接超过 2 秒
  （`FLASH_CJK_SERVER_GRACE_MS`）时，服务删除自己的 socket 并退出。最后
  一个实例离开时服务随之消失——没有轮询、没有守护进程管理、没有配置。
- **内存**：仅一个常驻进程，约 12.4 MB RSS，只在至少一个 Neovim 实例
  使用它时存在，外加每次按键约 0.04 ms 的 Unix domain socket 往返。
  CPU/电池开销取决于你的输入量，而不是进程启动的频率。
- **自动回退**：传输层偶发故障（超时、崩溃）会让该次按键回退到逐键
  spawn 传输，并异步恢复服务；连续失败会触发熔断器，退到 vim-regex
  路径。Windows 与超长 socket 路径（`sun_path` 上限）保持 spawn 传输。

二进制约 1.8 MB，静态携带数据表，无运行时依赖。当常驻内存紧张或进程
启动受限时，建议直接用纯 vim-regex 路径（即索性不构建二进制）。

</details>

在你自己的机器上复现：

```sh
cargo build --release --manifest-path rust/Cargo.toml
nvim -l benches/compare.lua # writes benches/results.json
uv run benches/gen_svg.py   # regenerates assets/benchmark.svg
```

## 📚 延伸阅读

| 目标             | 阅读                                                                       |
| ---------------- | -------------------------------------------------------------------------- |
| 了解系统         | [ARCHITECTURE.md](./ARCHITECTURE.md)                                       |
| 开发与验证       | [DEVELOPMENT.md](./DEVELOPMENT.md)                                         |
| 参与贡献         | [CONTRIBUTING.md](./CONTRIBUTING.md)                                       |
| 交给 AI 代理     | [AGENTS.md](./AGENTS.md)                                                   |
| 原生匹配器设计   | [rust/README.md](./rust/README.md)                                         |
| 阅读其他语言版本 | [简体中文](README.zh.md) · [日本語](README.ja.md) · [한국어](README.ko.md) |

## 📄 许可证

MIT——见 [LICENSE](./LICENSE)。数据衍生自
[Unicode Unihan 数据库](https://www.unicode.org/)（Unicode License）。感谢
[flash-zh.nvim](https://github.com/rainzm/flash-zh.nvim) 与
[hop-zh-by-flypy](https://github.com/zzhirong/hop-zh-by-flypy)。
