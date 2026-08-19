# flash-cjk.nvim

基于 [flash.nvim](https://github.com/folke/flash.nvim) 与小鹤双拼的 Neovim 中日韩三语跳转插件(fork 自 [flash-zh.nvim](https://github.com/rainzm/flash-zh.nvim))。

输入罗马音/两拼键序或拼音即可跳转到屏幕上任意的中日韩文字符:

- 中文:输入拼音(小鹤双拼)或拼音首字母,`ni` → 你,`r` → 日
- 日语:输入罗马音前缀,`ni` → 日/に/ニ,`kyo` → 京,`sha` → しゃ/社,`go` → 語
- 韩语:罗马音与两拼(두벌식)同时生效,`kim`/`gim` → 김,`annyeo`/`dkss` → 안녕,`seoul` → 서울,`dkswek` → 앉다
- 三语同时生效:`日` 既可以用拼音 `r` 命中,也可以用罗马音 `ni` 命中
- 假名直接用罗马音命中:`ka` → か/カ,Hepburn 与训令式(`si`/`shi`、`tu`/`tsu`)均支持

![iShot_2023-10-05_19 32 53](https://github.com/rainzm/flash-zh.nvim/assets/22927169/4c3ca124-0fee-48a2-b7c6-17391afe8d0e)

## 安装

- 依赖于 [flash.nvim](https://github.com/folke/flash.nvim)
- 使用 [lazy.nvim](https://github.com/folke/lazy.nvim) 进行安装:

```lua
return {{
    "fang2hou/flash-cjk.nvim",
    event = "VeryLazy",
    dependencies = "folke/flash.nvim",
    keys = {{
        "s",
        mode = {"n", "x", "o"},
        function()
            require("flash-cjk").jump({})
        end,
        desc = "Flash between Chinese/Japanese/Korean"
    }}
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

旧模块名 `flash-zh` 仍然可用(`require("flash-zh")` 会转发到 `flash-cjk`),已有配置无需修改。

## 使用

1. label 默认使用小写字母,通过自定义 `flash.nvim` 的 labeler,避免小写 label 和输入字母的冲突:某个匹配的下一个可能输入字母不会被分配为 label。
2. `jump` 的参数会传递给 `flash.nvim`。

**如果想要跳转的地方没有 label 出现,接着输入即可,和查找一样。**

### 输入中强制指定语言

输入过程中随时按 **`C-c` / `C-j` / `C-k` / `C-e`** 把匹配锁定到中文 / 日语 / 韩语 / 英文,立即重新计算:

- 输入 `ti` 会同时命中中文(梯/踢…)和日语(`ち` 的训令式拼写);按下 `C-c` 后只剩中文解释,`ち` 不再匹配
- `C-j` 锁定日语、`C-k` 锁定韩语、`C-e` 锁定英文(仅字面匹配);锁定后再按另一个键直接切换
- 锁定标记保留在输入串里,**退格删掉标记即恢复三语匹配**
- 锁定期间英文字面匹配(`original`)不受影响

键位可以自定义(或设为 `false` 禁用):

```lua
require("flash-cjk").setup({
    force_keys = {
        cn = "<C-c>",
        jp = "<C-j>",
        ko = "<C-k>",
        eo = "<C-e>",
    },
})
```

实现说明:按键字节与锁定标记是解耦的——`C-j` 的换行字节不会进入 flash 的输入缓冲(标记使用内部安全字节);`C-c` 的中断信号在 flash-cjk 跳转活跃时被拦截并转发给锁定动作,普通 flash 跳转(如 `/` 搜索)不受影响、`C-c` 仍按原样退出。

### 语言开关

四类匹配器可以独立开关,自由组合:

```lua
-- 全局开关(setup)
require("flash-cjk").setup({
    langs = {
        cn = true,       -- 中文拼音匹配(小鹤双拼 + 拼音首字母)
        jp = true,       -- 日语罗马音匹配(汉字读音 + 假名)
        ko = true,       -- 韩语匹配(罗马音 + 两拼键序)
        original = true, -- 英文字母字面匹配(flash.nvim 原生行为)
        -- alpha_mixing = false, -- 性能选项:不再解释"字母与语言段混排"的输入,
                              -- 长输入正则更小更快,代价见下文说明
    },
})

-- 单次跳转覆盖
require("flash-cjk").jump({ langs = { cn = false } })          -- 本次只匹配日/英文
require("flash-cjk").jump({ langs = { jp = false } })          -- 本次只匹配中/英文
require("flash-cjk").jump({ langs = { original = false } })    -- 本次只匹配中日文
require("flash-cjk").jump({ langs = { cn = true, jp = true, original = false } }) -- 纯 CJK
```

单语言使用者只需留下一个开关。注意:

- 关闭 `original` 后,数字、大写字母等非小写字母字符仍按字面匹配;完全无法解释的输入(如 `n.`)会退化为字面匹配。
- 标点映射跟随语言开关隔离:`cn` 关闭时 `,` 匹配 `、`(日语顿号)而不再匹配 `,`(全角逗号);`。` 为中日共用句号,始终可匹配;`-` → `ー` 属于 `jp`。

### 韩语匹配规则

- 谚文按音节结构(初声×中声×终声)程序分解,匹配正则使用码点区间(`[기-깋]`),无词典数据。
- 罗马音:文化观光部 2000 式为主,兼收 McCune-Reischauer 常见拼写(`kim`/`gim`、`park`/`bak`、`lee`/`ri`);每音节按罗马音前缀(1-4 字母)匹配,`han` → 한,`hak` → 학。
- 两拼(두벌식):标准键位(`r`=ㄱ、`k`=ㅏ、`s`=ㄴ…),`dkss` → 안녕,`gkrry` → 학교,复合终声 `dkswek` → 앉다;紧音(ㄲㄸㅃㅆㅉ)需要 shift,两拼侧不覆盖,请用罗马音(`kk`)。
- 元音单字母段(아=a、이=i、오=o…)在输入中间位置有效,与日语元音规则一致:`ai` → 아이,`oi` → 오이。
- `alpha_mixing = false`(性能选项):默认为 `true`,保留"字母与语言段混排"的解释(如 `nihao` 的 n+i+ha+o 变体),是原版 flash-zh 语义;设为 `false` 后只保留纯英文链与纯语言链,三语长输入(4+ 字母)的最差延迟约降低 40-60%,代价是混排目标的可达性。按需开启。

### 已知限制:macOS 文件名的 NFD 谚文

macOS 文件系统存储的韩文文件名是 NFD 分解形式(jamo 序列,如 `ㅎ+ㅏ+ㄴ` 而非预组合的 `한`),两种匹配路径(正则与 Rust)都只匹配 NFC 预组合音节。常规代码/文档缓冲区内容是 NFC,不受影响;若需在 oil/netrw 等文件名缓冲区跳转韩文,此为已知限制。

### 日语匹配规则

- 汉字:使用 [Unicode Unihan](https://www.unicode.org/charts/unihan.html) 的 `kJapanese`/`kJapaneseOn`/`kJapaneseKun` 读音(音读+训读),按罗马音前缀匹配,前缀最长 3 个字母(`n` / `ni` / `nic` 均可命中 日)。
- 假名:单假名按其罗马音的全部常见拼写匹配(含 `si`/`shi`/`ci` 等变体);拗音两字符组合按合并后的音节匹配(`sha` → しゃ/シャ)。
- 促音 `っ` 与长音 `ー`:`-` 键匹配 `ー`,`った` 这类文本通过逐假名输入自然命中。
- 标点:`[`/`]` → 「」『』,`,` → 、,`!` → !。

### 自定义匹配字符

- 你可以覆盖、或是追加字符到默认的匹配字符集。

    ```lua
    require('flash-cjk').setup {
        char_map = {
            -- Override default mapping in `flypy.comma`
            comma = {
                [']'] = ']」', -- A string of chars to match for, with no separator. No need to escape.
                ['!'] = '!！', -- You can add a symbol that isn't present in the default table.
            },
            -- Append to `flypy.comma`
            append_comma = {
                ['.'] = '…',
            },
            -- Append to `flypy.char1patterns`
            append_char1 = {
                ['a'] = 'äÄ',
            },
            -- Append to `flypy.char2patterns`
            append_char2 = {},
        }
    }
    ```

## Rust 加速(可选)

内置一个 Rust 原生匹配器,构建一次后自动启用,长输入每键延迟从 55-80ms 降到 1-3ms(对比 vim 正则路径 3.8x-76x):

```sh
cd rust && cargo build --release
```

二进制不存在或调用失败时自动回退到纯 Lua(vim 正则)路径,行为完全一致(有逐项严格交叉验证保障)。详见 [rust/README.md](rust/README.md)。

## 测试

```sh
nvim --headless +"lua dofile('tests/run.lua')" +qa!        # 功能 + 集成 + 端到端
nvim --headless -l tests/cross_validate_rust.lua            # Rust 与 vim 正则严格交叉验证
cd rust && cargo test && cargo clippy && cargo fmt --check  # Rust 单元 + benchmark
```

首次运行会自动克隆 flash.nvim 到 `.deps/`。

## 数据再生成

日语读音表由 `scripts/gen_jp_data.py` 从 Unihan 数据库生成(约 13,000 个汉字 + 全部假名):

```sh
uv run scripts/gen_jp_data.py            # 自动下载 Unihan.zip
uv run scripts/gen_jp_data.py path/to/Unihan_Readings.txt
nvim -l scripts/export_rs.lua            # 同步再生成 Rust 侧数据(rust/data/),避免两侧漂移
```

## 感谢

- [flash-zh.nvim](https://github.com/rainzm/flash-zh.nvim) 与 [hop-zh-by-flypy](https://github.com/zzhirong/hop-zh-by-flypy)
- [Unicode Unihan Database](https://www.unicode.org/)(数据来源,Unicode License)
- Migemo / [vim-kensaku](https://github.com/lambdalisue/vim-kensaku):罗马音搜索日语的先例
