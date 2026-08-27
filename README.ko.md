<div align="center">

# flash-cjk.nvim

[flash.nvim](https://github.com/folke/flash.nvim)에 중국어·일본어·한국어 텍스트 점프 기능을 추가합니다.

[![Validate](https://github.com/fang2hou/flash-cjk.nvim/actions/workflows/validate.yml/badge.svg)](https://github.com/fang2hou/flash-cjk.nvim/actions/workflows/validate.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](./LICENSE)

[English](README.md) · [简体中文](README.zh.md) · [日本語](README.ja.md) · **한국어**

</div>

[flash.nvim](https://github.com/folke/flash.nvim)은 강력하고 유연한 Neovim 점프 플러그인이지만 주로 ASCII 텍스트를 대상으로 설계되어 CJK 텍스트에서는 사용성이 제한됩니다. **flash-cjk.nvim**은 이 매칭 기능을 확장해 익숙한 입력 방식으로 중국어·일본어·한국어 텍스트를 검색하고 점프할 수 있게 하며, 기존 ASCII 리터럴 매칭은 그대로 유지합니다. 또한 선택적으로 사용할 수 있는 Rust 네이티브 매처를 제공해 다국어·혼합 입력·긴 쿼리 상황에서 지연 시간을 크게 줄여 줍니다.

기본 flash.nvim의 매칭에 더해 다음 입력 방식도 지원합니다:

- 🇨🇳 **간체 중국어**: 샤오헤 쌍병음
- 🇯🇵 **일본어**: 로마자
- 🇰🇷 **한국어**: 두벌식(Dubeolsik) 또는 로마자

https://github.com/user-attachments/assets/37599dab-b0c6-4d90-8463-cb4706841ac3

## 🚀 설치

Neovim ≥ 0.10과 [flash.nvim](https://github.com/folke/flash.nvim)이 필요합니다. Rust toolchain은 선택 사항이며 네이티브 매처를 빌드할 때만 필요합니다. [lazy.nvim](https://github.com/folke/lazy.nvim)으로 설치합니다:

```lua
{
	"fang2hou/flash-cjk.nvim",
	event = "VeryLazy",
	dependencies = {
		"folke/flash.nvim",
		keys = { { "s", false } },
	},
	-- 선택 사항: Rust 네이티브 매처.
	-- 다국어와 긴 입력에서 성능 향상이 큽니다. 필요하지 않다면 이 줄을 삭제하세요.
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

## ⚙️ 설정

기본 설정:

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

각 언어의 매칭 참여 여부를 설정할 수 있습니다. `enabled = false`로 두면 `priority` 설정과 관계없이 해당 언어는 검색 대상에서 제외됩니다.

`filter_key`는 검색 도중 **특정 언어로 고정**할 때 사용합니다. 고정하면 해당 언어와 ASCII 리터럴 매칭 결과만 남습니다. 기본 단축키:

| 언어        | 코드   | 잠금 키 |
| ----------- | ------ | ------- |
| 간체 중국어 | `zhcn` | `<C-c>` |
| 일본어      | `ja`   | `<C-j>` |
| 한국어      | `ko`   | `<C-k>` |
| ASCII       | `en`   | `<C-e>` |

`en`은 내장 언어라 `languages`에 따로 설정하지 않아도 됩니다.

### `priority`

여러 언어가 동시에 매칭되면 `priority = { "zhcn", "ja", "ko" }`가 매칭 결과에 Flash 라벨을 할당하는 우선순위를 정합니다. 앞에 있는 언어일수록 우선순위가 높습니다.

### `mixed_input`

하나의 쿼리에 서로 다른 언어의 입력 코드를 섞어 사용할 수 있습니다. 아래 사용법 예시의 혼합 입력을 참고하세요.

## ⌨️ 사용법

사용 방법은 flash.nvim과 거의 같습니다. `s`를 누른 다음 대상 텍스트의 입력 코드를 입력하면 됩니다. 아래 예시에서는 트리거 키 `s`를 포함한 전체 키 시퀀스를 보여 줍니다.

```text
English, a中文，日本語, 한국어. Hello, 你好，こんにちは、안녕하세요.
```

### ASCII

`si`를 입력하면(`s`로 flash-cjk를 시작하고 `i`를 쿼리로 사용) `English`의 `i`에 매칭됩니다. 일반 flash.nvim과 동일하게 동작합니다.

### 혼합 입력

`sav`를 입력하면 「a中」에 매칭됩니다. `a`는 ASCII로 리터럴 매칭되고, `v`는 샤오헤 쌍병음에서 「中」의 입력 코드 접두사입니다.

### 다국어 매칭

`sn`을 입력하면 쿼리 문자 `n`이 다음 항목을 동시에 매칭합니다:

- `n`: ASCII 알파벳
- `中`: 일본어 로마자 `naka`
- `日`: 일본어 로마자 `nichi`
- `你`: 중국어 샤오헤 쌍병음 `ni`
- `ん`: 일본어 로마자 `nn`
- `に`: 일본어 로마자 `ni`
- `안`: 한국어 로마자 `an`

후보가 너무 많으면 언제든 특정 언어로 고정해 범위를 좁힐 수 있습니다:

| 키      | 남는 매칭      |
| ------- | -------------- |
| `<C-c>` | 중국어 + ASCII |
| `<C-j>` | 일본어 + ASCII |
| `<C-k>` | 한국어 + ASCII |
| `<C-e>` | ASCII 전용     |

예를 들어 `<C-c>`를 누르면 `n`과 `你`만 남습니다. 백스페이스로 필터를 해제하거나 다른 잠금 키를 눌러 바로 전환할 수 있습니다.

## ⚡ 성능

flash-cjk.nvim에는 두 가지 매칭 경로가 있습니다. Neovim/Vim regex 매칭과 선택적으로 사용할 수 있는 Rust 네이티브 매처입니다. 단일 언어와 짧은 입력에서는 둘 다 지연이 낮고, 차이는 다국어·긴 입력·후보 텍스트가 많은 상황에서 더 뚜렷해집니다. 네 언어 전체 조합 벤치마크 결과입니다:

|                  | vim-regex |        Rust |            가속 |
| ---------------- | --------: | ----------: | --------------: |
| 전체 평균        |   9.04 ms | **0.40 ms** |           22.5× |
| 전체 p95         |   33.1 ms | **1.56 ms** |           21.3× |
| 일부 고부하 상황 |           |             | **최대 약 53×** |

vim-regex의 부하가 가장 큰 시나리오에서는 `ja`를 포함한 조합의 평균이 30 ms를 넘고 p95는 276 ms에 달합니다. Rust 매처는 주로 이런 극단적인 상황에서 입력 지연을 낮추기 위해 사용합니다.

### Rust 상주 서비스

Rust 매처는 처음 사용할 때 상주 서비스를 자동으로 시작하며, 이후 쿼리는 같은 프로세스를 재사용합니다. 따라서 매칭할 때마다 새 프로세스를 만드는 오버헤드를 피할 수 있습니다. 여러 Neovim 인스턴스가 하나의 서비스를 공유하므로 인스턴스마다 별도로 실행되지 않습니다.

<details>
<summary><strong>전체 벤치마크: vim-regex vs Rust matcher</strong></summary>

<p align="center">
  <img
    src="assets/benchmark.svg"
    alt="전체 15개 언어 조합 매트릭스에서 vim-regex 경로와 Rust matcher의 키 입력당 지연"
    width="720"
  >
</p>

테스트는 네 언어 `zhcn`(간체 중국어), `ja`(일본어), `ko`(한국어), `en`(ASCII)를 대상으로 하며, 15개 언어 조합 × 70 윈도우 = 1,050개 윈도우를 생성합니다. 각 윈도우에는 20–60행의 텍스트가 포함되며 해당 언어 조합에 맞는 내용만 생성합니다. 테스트에서는 1–6개의 적절한 쿼리 문자를 입력하면서 실제 vim-regex 경로와 Rust 상주 서비스 경로의 키 입력당 지연을 비교합니다.

### 단일 언어

| 윈도우 언어 | vim-regex 평균 | Rust server | 비율 | vim-regex p95 | server p95 |
| ----------- | -------------: | ----------: | ---: | ------------: | ---------: |
| `ja`        |        1.04 ms |     0.15 ms | 7.2× |        4.4 ms |    0.41 ms |
| `zhcn`      |        0.21 ms |     0.09 ms | 2.4× |        0.5 ms |    0.12 ms |
| `ko`        |        0.08 ms |     0.08 ms | 1.0× |        0.2 ms |    0.11 ms |
| `en`        |        0.07 ms |     0.09 ms | 0.8× |        0.1 ms |    0.13 ms |

### 두 언어

| 윈도우 언어   | vim-regex 평균 | Rust server |  비율 | vim-regex p95 | server p95 |
| ------------- | -------------: | ----------: | ----: | ------------: | ---------: |
| `ja` + `en`   |       32.66 ms |     0.62 ms | 52.9× |      144.2 ms |    2.06 ms |
| `ko` + `en`   |        4.88 ms |     0.76 ms |  6.4× |       35.4 ms |    4.45 ms |
| `zhcn` + `en` |        4.44 ms |     0.41 ms | 11.0× |       44.3 ms |    3.32 ms |
| `ja` + `ko`   |        1.55 ms |     0.15 ms | 10.2× |        5.2 ms |    0.32 ms |
| `zhcn` + `ja` |        1.17 ms |     0.16 ms |  7.2× |        6.5 ms |    0.36 ms |
| `zhcn` + `ko` |        0.26 ms |     0.10 ms |  2.5× |        0.6 ms |    0.16 ms |

### 세 언어

| 윈도우 언어          | vim-regex 평균 | Rust server |  비율 | vim-regex p95 | server p95 |
| -------------------- | -------------: | ----------: | ----: | ------------: | ---------: |
| `zhcn` + `ja` + `en` |       32.18 ms |     0.98 ms | 32.8× |      276.1 ms |    4.81 ms |
| `ja` + `ko` + `en`   |       22.53 ms |     0.81 ms | 28.0× |      144.5 ms |    4.71 ms |
| `zhcn` + `ja` + `ko` |       10.05 ms |     0.36 ms | 28.0× |       50.4 ms |    1.09 ms |
| `zhcn` + `ko` + `en` |        5.89 ms |     0.57 ms | 10.3× |       36.0 ms |    2.69 ms |

### 네 언어

| 윈도우 언어                 | vim-regex 평균 | Rust server |      비율 | vim-regex p95 |  server p95 |
| --------------------------- | -------------: | ----------: | --------: | ------------: | ----------: |
| `zhcn` + `ja` + `ko` + `en` |       18.67 ms |     0.71 ms |     26.2× |      100.8 ms |     4.30 ms |
| **전체(1,050개 윈도우)**    |    **9.04 ms** | **0.40 ms** | **22.5×** |   **33.1 ms** | **1.56 ms** |

</details>

## 🛠️ 개발

### AI 코딩 에이전트 사용

저장소를 코딩 에이전트에 바로 넘기려면 다음 지시를 사용하세요:

```text
Work in this repository. Read AGENTS.md at the repository root first and follow it.
```

### 로컬 개발

프로젝트는 모든 개발 의존성과 작업을 [mise](https://mise.jdx.dev/)로 관리합니다. mise를 설치한 다음 실행합니다:

```bash
mise install
mise run test
```

`mise run`을 실행하면 나머지 작업(`check`, `e2e`, `codegen`, `format`)을 모두 확인할 수 있습니다. 자세한 내용은 [DEVELOPMENT.md](./DEVELOPMENT.md)를 참고하세요.

## 📚 더 읽기

| 목적                 | 문서                                                                     |
| -------------------- | ------------------------------------------------------------------------ |
| 시스템 이해          | [ARCHITECTURE.md](./ARCHITECTURE.md)                                     |
| 개발과 검증          | [DEVELOPMENT.md](./DEVELOPMENT.md)                                       |
| 기여하기             | [CONTRIBUTING.md](./CONTRIBUTING.md)                                     |
| AI 에이전트에 넘기기 | [AGENTS.md](./AGENTS.md)                                                 |
| 네이티브 매처 설계   | [rust/README.md](./rust/README.md)                                       |
| 다른 언어로 읽기     | [English](README.md) · [简体中文](README.zh.md) · [日本語](README.ja.md) |

## 📄 라이선스

MIT — 자세한 내용은 [LICENSE](./LICENSE)를 참고하세요. 데이터는
[Unicode Unihan 데이터베이스](https://www.unicode.org/)에서 파생되었습니다(Unicode
License). [flash-zh.nvim](https://github.com/rainzm/flash-zh.nvim)과
[hop-zh-by-flypy](https://github.com/zzhirong/hop-zh-by-flypy)에 감사드립니다.
