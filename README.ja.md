<div align="center">

# flash-cjk.nvim

Neovimで簡体字中国語・日本語・韓国語の任意の文字に、そのピンイン・
ローマ字・ローマ字表記を入力してジャンプできます — IMEの切り替えは不要です。
[flash.nvim](https://github.com/folke/flash.nvim) をベースに、
[flash-zh.nvim](https://github.com/rainzm/flash-zh.nvim) からフォークして作られました。

[English](README.md) · [简体中文](README.zh.md) · [日本語](README.ja.md) · [한국어](README.ko.md)

[![Validate](https://github.com/fang2hou/flash-cjk.nvim/actions/workflows/validate.yml/badge.svg)](https://github.com/fang2hou/flash-cjk.nvim/actions/workflows/validate.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](./LICENSE)

</div>

ジャンプ先のCJK文字をCJK入力で指定するとなると、操作の途中でIMEと格闘する
ことになります。flash-cjkなら手元はASCIIのままです。`ni` は 你 / 日 / に / ニ
に届き、`r` はピンインの声母で 日 にヒットし、`dkss` は2ボル式（두벌식）
のキー列で 안녕 にヒットします。その一方で、素のアルファベットは
flash.nvimとまったく同じようにリテラル一致します。

- 対応範囲：簡体字中国語のピンイン（小鶴双拼と声母）、日本語のローマ字
  （漢字の読み＋かな、ヘボン式と訓令式）、韓国語（RRローマ字表記と
  2ボル式（두벌식）のキー列）、ASCIIリテラル — すべて同時に、かつ独立に
  オン/オフできます
- 対象外：flash.nvim自体の機能（treesitterジャンプ、リモートなど）の置き
  換え、IME統合、NFDの韓国語ファイル名（下記「機能」の既知の制限を参照）
- 状態：活発に開発中

## 🚀 使い方

[flash.nvim](https://github.com/folke/flash.nvim) と Neovim ≥ 0.10 が必要です。
[lazy.nvim](https://github.com/folke/nvim-lazy) でインストールします：

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

lazy.nvim を使っていない場合は、上の `opts` と同じオプションで
`require("flash-cjk").setup({ ... })` を自分で呼び出してください。

`s` を押し、入力し、ジャンプ — この一連の流れはflash.nvimと同じです。目的
の文字にまだラベルが表示されていないときは、（検索と同様に）入力を続けて
ください。ラベルには小文字が使われ、表示中のマッチに対して次に入力しうる
文字と衝突することはありません。

**AIコーディングエージェントで使う** — リポジトリをエージェントに任せるときは、
以下を貼り付けてください：

```text
Work in this repository. Read AGENTS.md at the repository root first and follow it.
```

**プラグインの開発やベンチマーク**には、macOS または Linux での
[mise](https://mise.jdx.dev/) が必要です：

```bash
mise install
mise run test
```

`mise run` で他のすべてのタスク（`check`、`e2e`、`codegen`、`format`）を
一覧できます。詳しくは [DEVELOPMENT.md](./DEVELOPMENT.md) を参照してください。

<details>
<summary>Rustアクセラレータ：いつ必要で、いつ不要か</summary>

上の `build =` 行は、cargoが利用可能な場合にのみ任意のネイティブマッチャーを
ビルドします。手動ビルドは `cd rust && cargo build --release` です。Rustは
必須ではありません。バイナリがなくてもプラグインは黙ってvim-regexパスを
使います（結果は同一。相互検証で保証）。サンドボックスや制限された環境では
`build =` 行を削除してください — 純Luaパスはコンパイラ不要で、プロセスも
起動しません。

</details>

## 💡 概念

- **解釈（Interpretations）** — キーストローク列はリテラル文字と言語コード
  （ピンイン、ローマ字、ローマ字表記）に分割されます。同じ入力の妥当な読みは
  すべて一度に到達可能なままです。`ni` は簡体字中国語（你）と日本語
  （日 / に / ニ）の両方に一致します。
- **言語の固定（Language lock）** — 入力中に `C-c` / `C-j` / `C-k` / `C-e` を
  押すと、一致対象を 簡体字中国語 / 日本語 / 韓国語 / 英語 に固定し、即座に
  再計算します。`C-c` の後は簡体字中国語の読みだけが残り、ちは一致しなく
  なります。固定は入力文字列に積まれていくため、**マーカーをバックスペース
  で削除すると固定が解除されます**。別の固定キーを押すと即座に切り替わり
  ます。固定キーは言語ごとに設定できます（`force_key`、`false` で無効化）。
- **混合入力（Mixed input）** — キーストローク列は、一部をリテラル、一部を
  言語コードとして読めます。`nn` と打つと `日n` に届きます（ローマ字 `n` +
  リテラル `n`）。ミラーの `n日` は、先頭リテラルが常に許可されるため、
  どのモードでも一致します。`mixed_input = false` にすると落ちるのは
  「言語→リテラル」の逆の形だけで、3言語の長い入力で最悪ケースのレイテンシが
  40〜60%減ります — 長い入力で目に見えて遅延しない限り、デフォルトのままに
  してください。
- **ジャンプ単位の言語セット** — 各言語は `languages` テーブルで独立に設定
  します（`setup` によるグローバル指定、またはジャンプ単位：
  `jump({ "ja", "ko", "en" })` はそのジャンプでは簡体字中国語に一致しません）。
  `setup` は深くマージし、`true`/`false` の簡略記法は `enabled` を切り替え
  ます。句読点はスイッチに従います：`zhcn` がオフのとき、`,` は，（全角
  コンマ）ではなく 、（日本語）に一致します。

## ✨ 機能

- **簡体字中国語（`zhcn`）** — 小鶴双拼（Xiaohe double-pinyin）の2キー
  コードか、ピンインの声母を入力します：`ni` → 你、`r` → 日。すべての漢字が
  2キーコードで到達可能で、1文字だけならその声母で始まるピンインの漢字
  すべてに一致します。スキームは `"xiaohe"`（現時点で唯一。今後追加可能）。
- **日本語（`ja`）** — ローマ字でマッチします：`ni` は 日 に、`ti` は ち
  （訓令式）にヒットします。漢字は Unicode Unihan 由来の読み（約13,000字）を、
  3文字までのローマ字プレフィックスで一致させます（`n`/`ni`/`nic` はいずれも
  日 にヒット）。かなはその音節の一般的なローマ字表記すべてに一致します
  （`si`/`shi`、`tu`/`tsu`）。拗音のペアは1単位として一致します
  （`sha` → しゃ/シャ）。`-` は長音 ー に、`[` と `]` は 「」 と 『』 に、
  `,` は読点 、 に、`!` は ！ に一致します。
- **韓国語（`ko`）** — 2ボル式（두벌식、Dubeolsik、韓国の標準キーボード）の
  キー列：`dks` → 안、`gkrry` → 학교、`dkswek` → 앉다。またはローマ字表記：
  RR（Revised Romanization of Korean、로마자 표기법）に加えて一般的な
  マキューン＝ライシャワー式のつづり（`kim`/`gim` → 김）を、音節ごとに
  プレフィックス一致します。音節はプログラム的に字母（ジャモ）へ分解され
  ます — 辞書データは不要です。濃音のジャモは2ボル式ではシフトが必要なので、
  代わりにローマ字（`kk`）を使ってください。母音のみのセグメントは、日本語の
  母音と同様に入力途中でも機能します（`ai` → 아이）。
- **英語（`en`）** — 素のASCIIは、flash.nvim自体の検索とまったく同じように
  1文字ずつリテラル一致します。コードの識別子は言語解釈なしで到達可能です。
  `en` を無効にしても数字と大文字は引き続きリテラル一致し、有効などの言語も
  解釈できない入力（`n.` など）はリテラル一致へフォールバックします。
- **優先ラベル（Priority labels）** — `priority = { "ja", "zhcn" }` はラベル
  割り当ての順序を決めます。リストの前方の言語で到達できる一致が最も早い
  ラベルを受け取るため、主言語の目標は最も少ないラベルキーでジャンプでき
  ます。一致セットとジャンプのセマンティクスは変わらず、未設定なら位置順序
  のままです。

既知の制限：macOSは韓国語のファイル名をNFD（分解済みジャモ）で保存します。
両方のマッチパスはNFCの合成済み音節を対象とするため、oil/netrw のファイル名
バッファ内でのジャンプでは韓国語ファイル名に一致しません。通常のコード
バッファやドキュメントバッファはNFCなので影響を受けません。

## ⚡ パフォーマンス

短いプレフィックス（1〜2文字）なら、内蔵の vim-regex パスで中央値約
0.5 ms で応答します（1言語のみ有効なら 0.1〜0.9 ms）。重いのはこのパスでの
3言語の長い入力です：最も重い組み合わせで平均約 30 ms、p95 は 134〜243 ms
に達します。任意のネイティブマッチャーは最悪ケースを平坦化します — 平均は
全体で 8.5×、p95 テールは 6.7×（最も重い組み合わせで最大 27×）下がり、
正規表現の選択肢が Vim でコンパイルできなくなった（E872）パターンでも
動作し続けます。一度ビルドすると自動的に有効になります。

<p align="center">
  <img
    src="assets/benchmark.svg"
    alt="ベンチマーク：完全な 15 組み合わせ言語マトリクスにおける vim-regex 経路と常駐サーバー上のネイティブ Rust マッチャーのキーストロークあたりコスト"
    width="720"
  />
</p>

完全な言語組み合わせマトリクス（4 言語コード——`zhcn`（簡体字中国語）、
`ja`（日本語）、`ko`（韓国語）、`en`（英語）——の単一・2 つ・3 つ・4 つ
すべての組み合わせ、15 組 × 70 ウィンドウ = 1,050 個の 20–60 行生成
ウィンドウ）で、実際のキーストローク経路を測定しました。各行はその行の言語
のみを有効化し、それらの言語からウィンドウテキストをサンプリングし、その
言語で妥当な 1–6 キーストロークを入力します（`en` 単独行は純粋な ASCII
単語）。シードは固定で再現可能です。

**Rust（server）** はネイティブ経路であり、実際のキーストロークが使う経路
です。キーストロークごとに常駐マッチャーサーバーへ 1 リクエストを送ります
（下記参照）。

単一言語——1 つの言語のみ有効：

| ウィンドウ言語 | vim-regex 平均 | Rust server |  比率 | vim-regex p95 | server p95 |
| -------------- | -------------: | ----------: | ----: | ------------: | ---------: |
| `ja`           |        1.22 ms |     0.16 ms |  7.8× |        4.6 ms |    0.40 ms |
| `zhcn`         |        0.20 ms |     0.09 ms |  2.2× |        0.5 ms |    0.14 ms |
| `en`           |        0.08 ms |     0.11 ms | 0.75× |        0.1 ms |    0.14 ms |
| `ko`           |        0.08 ms |     0.10 ms | 0.81× |        0.2 ms |    0.16 ms |

2 言語——2 つを有効：

| ウィンドウ言語 | vim-regex 平均 | Rust server |  比率 | vim-regex p95 | server p95 |
| -------------- | -------------: | ----------: | ----: | ------------: | ---------: |
| `ja` + `en`    |       29.99 ms |     1.35 ms | 22.2× |      134.1 ms |    5.00 ms |
| `ko` + `en`    |        4.94 ms |     2.13 ms |  2.3× |       35.2 ms |   16.60 ms |
| `zhcn` + `en`  |        4.43 ms |     1.23 ms |  3.6× |       44.8 ms |   11.94 ms |
| `ja` + `ko`    |        1.49 ms |     0.18 ms |  8.2× |        4.4 ms |    0.50 ms |
| `zhcn` + `ja`  |        1.04 ms |     0.16 ms |  6.4× |        3.6 ms |    0.34 ms |
| `zhcn` + `ko`  |        0.24 ms |     0.13 ms |  1.8× |        0.6 ms |    0.25 ms |

3 言語——3 つを有効：

| ウィンドウ言語       | vim-regex 平均 | Rust server |  比率 | vim-regex p95 | server p95 |
| -------------------- | -------------: | ----------: | ----: | ------------: | ---------: |
| `zhcn` + `ja` + `en` |       29.12 ms |     2.43 ms | 12.0× |      243.4 ms |   14.79 ms |
| `ja` + `ko` + `en`   |       19.48 ms |     2.10 ms |  9.3× |      129.7 ms |   15.47 ms |
| `zhcn` + `ja` + `ko` |        9.07 ms |     0.67 ms | 13.6× |       47.5 ms |    2.40 ms |
| `zhcn` + `ko` + `en` |        5.80 ms |     1.83 ms |  3.2× |       32.9 ms |   10.88 ms |

4 言語すべて有効：

| ウィンドウ言語               | vim-regex 平均 | Rust server |     比率 | vim-regex p95 |  server p95 |
| ---------------------------- | -------------: | ----------: | -------: | ------------: | ----------: |
| `zhcn` + `ja` + `ko` + `en`  |       16.26 ms |     1.90 ms |     8.6× |       95.0 ms |    14.04 ms |
| **全体（1,050 ウィンドウ）** |    **8.23 ms** | **0.97 ms** | **8.5×** |   **29.1 ms** | **4.35 ms** |

**方法論。** 各ケースは 1 回のウォームアップの後、3 回の実測の中央値
（`vim.uv.hrtime`）を報告します。行はグループ内で vim-regex 平均順に並べて
います。比率は vim-regex 平均 ÷ Rust server 平均で、1× 未満なら純 Lua 経路が
高速です。vim-regex の計測は実際のキーストロークが払うすべて（パターン分割、
選択肢構築、`vim.regex()` コンパイル、可視行すべてのスキャン）を含みます。
Rust の計測は常駐サーバーへの 1 回の UDS リクエスト——実際のキーストロークと
完全に同じ転送です。今回の実行では 1,050 パターンのうち 0 件が Vim の NFA
キャプチャグループ上限（E872）に達しましたが、達しても Rust マッチャーは
動作し続けます。

**読み方。** サーバーはプロセス生成とデータテーブル構築を自身の起動時に
1 回だけ支払い、あとは 0.09–2.5 ms のフラットな帯で応答します。15 カテゴリ中
13 が Rust 優位で、残る 2 つ（`en`/`ko` 単独）も 0.08 対 0.10–0.11 ms と、
どちらも 0.2 ms 未満です。重要なのはテールです。最も重い組み合わせ
（`ja`+`en`、`zhcn`+`ja`+`en`）の p95 は vim-regex の 134–243 ms から
5.0–14.8 ms へ、全体の p95 も 29.1 ms から 4.4 ms へ下がります。

<details>
<summary>バックグラウンドサービス（Unix、設定不要）</summary>

バイナリが存在するとき、プラグインはユーザーごとに 1 つのマッチャー
サーバーを透過的に維持します：

- **ライフサイクル**：Neovim インスタンスはアイドルなセッション接続を開いて
  いる間だけ登録されます。Neovim を終了（あるいは `kill -9`）すると登録は
  即座に外れ、どのインスタンスも 2 秒間（`FLASH_CJK_SERVER_GRACE_MS`）接続
  していなければ、サーバーは自身のソケットを削除して終了します。最後の
  インスタンスが抜けるとサーバーも消えます——ポーリングもデーモン管理も
  設定も不要です。
- **メモリ**：常駐プロセスは 1 つ（約 12.4 MB RSS）で、少なくとも 1 つの
  Neovim インスタンスが使用している間だけ存在します。加えてキーストローク
  ごとに約 0.04 ms の Unix ドメインソケット往復がかかるだけです。CPU/
  バッテリーの消費は入力量に比例し、プロセス起動回数には比例しません。
- **自動フォールバック**：転送の一時的な失敗（タイムアウト、クラッシュ）は
  そのキーストロークを spawn 転送に落とし、サーバーを非同期で復活させます。
  失敗が続けばサーキットブレーカーが作動し vim-regex 経路へ落ちます。
  Windows と過長なソケットパス（`sun_path` 上限）は spawn 転送のままです。

バイナリは約 1.8 MB で、データテーブルを静的に埋め込み、ランタイム依存は
ありません。常駐メモリが乏しい環境やプロセス起動が制限される環境では、
純 vim-regex 経路（バイナリをビルドしない）を推奨します。

</details>

自分のマシンで再現するには：

```sh
cargo build --release --manifest-path rust/Cargo.toml
nvim -l benches/compare.lua # writes benches/results.json
uv run benches/gen_svg.py   # regenerates assets/benchmark.svg
```

## 📚 次に読むドキュメント

| 目的                       | ドキュメント                                                               |
| -------------------------- | -------------------------------------------------------------------------- |
| システムを理解する         | [ARCHITECTURE.md](./ARCHITECTURE.md)                                       |
| 開発と検証                 | [DEVELOPMENT.md](./DEVELOPMENT.md)                                         |
| 変更をコントリビュートする | [CONTRIBUTING.md](./CONTRIBUTING.md)                                       |
| エージェントに渡す         | [AGENTS.md](./AGENTS.md)                                                   |
| ネイティブマッチャーの設計 | [rust/README.md](./rust/README.md)                                         |
| 他の言語で読む             | [简体中文](README.zh.md) · [日本語](README.ja.md) · [한국어](README.ko.md) |

## 📄 ライセンス

MIT — [LICENSE](./LICENSE) を参照してください。データは
[Unicode Unihan Database](https://www.unicode.org/)（Unicode License）から
生成したものです。[flash-zh.nvim](https://github.com/rainzm/flash-zh.nvim) と
[hop-zh-by-flypy](https://github.com/zzhirong/hop-zh-by-flypy) に感謝します。
