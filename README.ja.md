<div align="center">

# flash-cjk.nvim

[flash.nvim](https://github.com/folke/flash.nvim) に、中国語・日本語・韓国語のテキストへのジャンプ機能を追加します。

[![Validate](https://github.com/fang2hou/flash-cjk.nvim/actions/workflows/validate.yml/badge.svg)](https://github.com/fang2hou/flash-cjk.nvim/actions/workflows/validate.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](./LICENSE)

[English](README.md) · [简体中文](README.zh.md) · **日本語** · [한국어](README.ko.md)

</div>

[flash.nvim](https://github.com/folke/flash.nvim) は強力で柔軟な Neovim ジャンププラグインですが、主に ASCII テキストを対象としているため、CJK テキストでは使い勝手に制限があります。**flash-cjk.nvim** はそのマッチング機能を拡張し、使い慣れた入力方式のまま中国語・日本語・韓国語のテキストを検索してジャンプできるようにします。既存の ASCII リテラルマッチは従来どおり動作します。さらに、オプションの Rust ネイティブマッチャーも用意しており、多言語・混合入力・長いクエリといった場面でレイテンシを大幅に抑えられます。

通常の flash.nvim のマッチングに加えて、次の入力方式によるマッチングに対応します：

- 🇨🇳 **簡体字中国語**：小鶴双拼
- 🇯🇵 **日本語**：ローマ字
- 🇰🇷 **韓国語**：두벌식（Dubeolsik）またはローマ字

https://github.com/user-attachments/assets/37599dab-b0c6-4d90-8463-cb4706841ac3

## 🚀 インストール

Neovim ≥ 0.10 と [flash.nvim](https://github.com/folke/flash.nvim) が必要です。Rust ツールチェーンはオプションで、ネイティブマッチャーをビルドする場合のみ必要です。[lazy.nvim](https://github.com/folke/lazy.nvim) でのインストール例：

```lua
{
	"fang2hou/flash-cjk.nvim",
	event = "VeryLazy",
	dependencies = {
		"folke/flash.nvim",
		keys = { { "s", false } },
	},
	-- オプショナル：Rust ネイティブマッチャー
	-- 多言語・長い入力では大きな性能向上が見込めます。不要ならこの行を削除してください。
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

## ⚙️ 設定

デフォルト設定：

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

言語ごとにマッチングへ参加するかどうかを設定できます。`enabled = false` にした言語は、`priority` の設定にかかわらず検索対象から外れます。

`filter_key` は検索中に**対象言語を固定する**ために使います。押すと、その言語と ASCII リテラルマッチの結果だけが残ります。デフォルトのキー：

| 言語         | コード | ロックキー |
| ------------ | ------ | ---------- |
| 簡体字中国語 | `zhcn` | `<C-c>`    |
| 日本語       | `ja`   | `<C-j>`    |
| 韓国語       | `ko`   | `<C-k>`    |
| ASCII        | `en`   | `<C-e>`    |

`en` は組み込みの言語なので、`languages` への設定は不要です。

### `priority`

複数の言語が同時にマッチした場合、`priority = { "zhcn", "ja", "ko" }` が Flash ラベルを割り当てる優先順位を決めます。リストの前方にある言語ほど優先度が高くなります。

### `mixed_input`

1 回のクエリに、異なる言語の入力コードを混在させられます。入力例は下の使い方の「混合入力」を参照してください。

### `char`

flash.nvim 内蔵の拡張文字モーション（flash の `modes.char`、デフォルトで有効）を CJK 対応にします。入力した 1 文字が、`s` ジャンプと同じ多言語エンジンでマッチされます。`fv` で「中」へジャンプでき（小鶴双拼の zhong の頭文字 `v`）、`ft` なら「中」（日本語訓令式ローマ字 `tyuu`）や「梯」（ピンイン `ti`）に到達します。`;`/`,` の循環、カウント、オペレータ待機時の挙動は flash ネイティブのモーションとまったく同じです。マッチングは 1 文字のみで、複数キーの読みを入力したい場合は `s` を使ってください。`setup({ char = false })` を設定すると、flash ネイティブの ASCII 専用の挙動に戻ります。

## ⌨️ 使い方

操作は flash.nvim とほぼ同じです。`s` を押し、目的のテキストに対応する入力コードを入力するだけです。以下の例では、トリガーキー `s` を含めた完全なキー列で示します。

```text
English, a中文，日本語, 한국어. Hello, 你好，こんにちは、안녕하세요.
```

### ASCII

`si` と入力すると（`s` で flash-cjk を起動し、`i` がクエリになります）、`English` の `i` にマッチします。通常の flash.nvim と同じ挙動です。

### 混合入力

`sav` と入力すると「a中」にマッチします。`a` は ASCII としてリテラルマッチし、`v` は小鶴双拼における「中」の入力コードのプレフィックスです。

### 文字モーション

同じエンジンは `f`/`t`/`F`/`T`（flash の拡張文字モーション）にも作用します。上のサンプル行では、`fv` で「中」へジャンプできます。

### 多言語マッチング

`sn` と入力すると、クエリ文字 `n` が次のすべてに同時にマッチします：

- `n`：ASCII のアルファベット
- `中`：日本語ローマ字 `naka`
- `日`：日本語ローマ字 `nichi`
- `你`：中国語小鶴双拼 `ni`
- `ん`：日本語ローマ字 `nn`
- `に`：日本語ローマ字 `ni`
- `안`：韓国語ローマ字 `an`

候補が多すぎる場合は、いつでも対象言語を固定して絞り込めます：

| キー    | 残るマッチ     |
| ------- | -------------- |
| `<C-c>` | 中国語 + ASCII |
| `<C-j>` | 日本語 + ASCII |
| `<C-k>` | 韓国語 + ASCII |
| `<C-e>` | ASCII のみ     |

たとえば `<C-c>` を押すと、`n` と `你` だけが残ります。バックスペースでフィルタを解除でき、別のロックキーを押せばそのまま切り替えられます。

## ⚡ パフォーマンス

flash-cjk.nvim には 2 つのマッチング経路があります。Neovim / Vim の regex マッチングと、オプションの Rust ネイティブマッチャーです。1 言語・短い入力ではどちらもレイテンシは低く、差が大きくなるのは多言語・長い入力・候補テキストが多い場面です。4 言語すべての組み合わせを含むベンチマークの結果：

|                  | vim-regex |        Rust |         高速化 |
| ---------------- | --------: | ----------: | -------------: |
| 全体の平均       |   9.04 ms | **0.40 ms** |          22.5× |
| 全体の p95       |   33.1 ms | **1.56 ms** |          21.3× |
| 一部の高負荷場面 |           |             | **最大約 53×** |

vim-regex の負荷が最も高い場面では、`ja` を含む組み合わせで平均が 30 ms を超え、p95 は 276 ms に達します。Rust マッチャーは、主にこうした極端なケースでの入力遅延を抑えるためのものです。

### Rust 常駐サービス

Rust マッチャーは初回使用時に常駐サービスを自動起動し、以降のクエリではそのプロセスを再利用します。これにより、マッチのたびにプロセスを作り直すオーバーヘッドを避けられます。また、複数の Neovim インスタンスで同じサービスを共有するため、エディタのインスタンスごとにサービスが起動することはありません。

<details>
<summary><strong>完全なベンチマーク：vim-regex vs Rust matcher</strong></summary>

<p align="center">
  <img
    src="assets/benchmark.svg"
    alt="完全な 15 組み合わせ言語マトリクスにおける vim-regex 経路と Rust matcher の 1 キーストロークあたりのレイテンシ"
    width="720"
  >
</p>

テストでは、`zhcn`（簡体字中国語）、`ja`（日本語）、`ko`（韓国語）、`en`（ASCII）の 4 言語を対象に、15 の言語組み合わせ × 70 ウィンドウ = 1,050 個のウィンドウを生成します。各ウィンドウには 20–60 行のテキストが含まれ、その言語組み合わせに対応する内容だけが生成されます。テスト中は妥当なクエリ文字を 1–6 個入力し、実際の vim-regex 経路と Rust 常駐サービス経路の 1 キーストロークあたりのレイテンシを比較します。

### 単一言語

| ウィンドウ言語 | vim-regex 平均 | Rust server | 比率 | vim-regex p95 | server p95 |
| -------------- | -------------: | ----------: | ---: | ------------: | ---------: |
| `ja`           |        1.04 ms |     0.15 ms | 7.2× |        4.4 ms |    0.41 ms |
| `zhcn`         |        0.21 ms |     0.09 ms | 2.4× |        0.5 ms |    0.12 ms |
| `ko`           |        0.08 ms |     0.08 ms | 1.0× |        0.2 ms |    0.11 ms |
| `en`           |        0.07 ms |     0.09 ms | 0.8× |        0.1 ms |    0.13 ms |

### 2 言語

| ウィンドウ言語 | vim-regex 平均 | Rust server |  比率 | vim-regex p95 | server p95 |
| -------------- | -------------: | ----------: | ----: | ------------: | ---------: |
| `ja` + `en`    |       32.66 ms |     0.62 ms | 52.9× |      144.2 ms |    2.06 ms |
| `ko` + `en`    |        4.88 ms |     0.76 ms |  6.4× |       35.4 ms |    4.45 ms |
| `zhcn` + `en`  |        4.44 ms |     0.41 ms | 11.0× |       44.3 ms |    3.32 ms |
| `ja` + `ko`    |        1.55 ms |     0.15 ms | 10.2× |        5.2 ms |    0.32 ms |
| `zhcn` + `ja`  |        1.17 ms |     0.16 ms |  7.2× |        6.5 ms |    0.36 ms |
| `zhcn` + `ko`  |        0.26 ms |     0.10 ms |  2.5× |        0.6 ms |    0.16 ms |

### 3 言語

| ウィンドウ言語       | vim-regex 平均 | Rust server |  比率 | vim-regex p95 | server p95 |
| -------------------- | -------------: | ----------: | ----: | ------------: | ---------: |
| `zhcn` + `ja` + `en` |       32.18 ms |     0.98 ms | 32.8× |      276.1 ms |    4.81 ms |
| `ja` + `ko` + `en`   |       22.53 ms |     0.81 ms | 28.0× |      144.5 ms |    4.71 ms |
| `zhcn` + `ja` + `ko` |       10.05 ms |     0.36 ms | 28.0× |       50.4 ms |    1.09 ms |
| `zhcn` + `ko` + `en` |        5.89 ms |     0.57 ms | 10.3× |       36.0 ms |    2.69 ms |

### 4 言語

| ウィンドウ言語               | vim-regex 平均 | Rust server |      比率 | vim-regex p95 |  server p95 |
| ---------------------------- | -------------: | ----------: | --------: | ------------: | ----------: |
| `zhcn` + `ja` + `ko` + `en`  |       18.67 ms |     0.71 ms |     26.2× |      100.8 ms |     4.30 ms |
| **全体（1,050 ウィンドウ）** |    **9.04 ms** | **0.40 ms** | **22.5×** |   **33.1 ms** | **1.56 ms** |

</details>

## 🛠️ 開発

### AI コーディングエージェントを使う

リポジトリをそのままコーディングエージェントに渡したい場合は、次の指示を貼り付けてください：

```text
Work in this repository. Read AGENTS.md at the repository root first and follow it.
```

### ローカル開発

このプロジェクトでは、開発用の依存関係とタスクをすべて [mise](https://mise.jdx.dev/) で管理しています。mise をインストールしたら、次のコマンドを実行します：

```bash
mise install
mise run test
```

`mise run` でその他のタスク（`check`、`e2e`、`codegen`、`format`）を一覧できます。詳細は [DEVELOPMENT.md](./DEVELOPMENT.md) を参照してください。

## 📚 ドキュメント

| 目的                       | ドキュメント                                                             |
| -------------------------- | ------------------------------------------------------------------------ |
| システムを理解する         | [ARCHITECTURE.md](./ARCHITECTURE.md)                                     |
| 開発と検証                 | [DEVELOPMENT.md](./DEVELOPMENT.md)                                       |
| コントリビュートする       | [CONTRIBUTING.md](./CONTRIBUTING.md)                                     |
| エージェントに渡す         | [AGENTS.md](./AGENTS.md)                                                 |
| ネイティブマッチャーの設計 | [rust/README.md](./rust/README.md)                                       |
| 他の言語で読む             | [English](README.md) · [简体中文](README.zh.md) · [한국어](README.ko.md) |

## 📄 ライセンス

MIT ライセンスです。詳しくは [LICENSE](./LICENSE) を参照してください。データは
[Unicode Unihan Database](https://www.unicode.org/)（Unicode License）をもとに
生成しています。[flash-zh.nvim](https://github.com/rainzm/flash-zh.nvim) と
[hop-zh-by-flypy](https://github.com/zzhirong/hop-zh-by-flypy) に感謝します。
