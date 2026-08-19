<div align="center">

# flash-cjk.nvim

IME를 전환하지 않고도 병음·로마지·로마자 표기를 입력해 Neovim 안의 한중일
문자 어디로든 점프하세요. [flash.nvim](https://github.com/folke/flash.nvim)을
기반으로 하며, [flash-zh.nvim](https://github.com/rainzm/flash-zh.nvim)에서
포크되었습니다.

[English](README.md) · [简体中文](README.zh.md) · [日本語](README.ja.md) · [한국어](README.ko.md)

[![Validate](https://github.com/fang2hou/flash-cjk.nvim/actions/workflows/validate.yml/badge.svg)](https://github.com/fang2hou/flash-cjk.nvim/actions/workflows/validate.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](./LICENSE)

</div>

## 왜 필요한가?

점프하려는 한중일 텍스트를 찾으려고 한중일 텍스트를 입력하는 것은, 동작
한가운데서 IME와 씨름하는 일입니다. flash-cjk는 손을 ASCII 안에 그대로
둡니다: `ni`는 日 / に / ニ에 닿고, `r`은 병음 초성으로 日을 찾으며,
`dkss`는 두벌식 키로 안녕에 닿습니다 — 나머지 평범한 영문자는 flash.nvim과
똑같이 문자 그대로 매칭됩니다.

- 다루는 범위: 중국어 병음(flypy와 초성), 일본어 로마지(한자 읽기와 가나,
  헵번식과 훈령식), 한국어(개정 로마자 표기와 두벌식 키 시퀀스), 리터럴
  ASCII — 모두 동시에 켤 수 있고 각각 독립적으로 켜고 끌 수 있습니다
- 다루지 않는 범위: flash.nvim 자체 기능 대체(treesitter 점프, remote 등);
  IME 연동; NFD 형태의 한글 파일명(알려진 제한 사항 참고)
- 상태: 활발히 개발 중

## 설치

[flash.nvim](https://github.com/folke/flash.nvim)이 필요하며,
[lazy.nvim](https://github.com/folke/nvim-lazy)으로 설치합니다:

```lua
return {{
    "fang2hou/flash-cjk.nvim",
    event = "VeryLazy",
    dependencies = "folke/flash.nvim",
    -- 선택 사항인 Rust 가속기("Rust 가속" 섹션 참고): 설치/업데이트 시점에
    -- 빌드되며, cargo가 없으면 플러그인이 대신 조용히 vim-regex 경로를
    -- 사용합니다. 빌드를 아예 건너뛰려면 이 줄을 삭제하세요.
    build = "cargo build --release --manifest-path=rust/Cargo.toml",
    keys = {{
        "s",
        mode = {"n", "x", "o"},
        function()
            require("flash-cjk").jump()
        end,
        desc = "Flash between Chinese/Japanese/Korean"
    }},
    opts = {
        languages = {
            zhcn = {force_key = "<C-c>"},  -- 기본값: 활성, 스킴 "xiaohe"
            ja = {force_key = "<C-j>"},    -- 기본 스킴: "roma"
            ko = {force_key = "<C-k>"},
            en = {force_key = "<C-e>"},    -- en에는 스킴 개념이 없음
        },
        alpha_mixing = true,
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

## 사용법

`s`를 누르고, 입력하고, 점프하세요 — flash.nvim과 같은 흐름입니다. 대상에
아직 라벨이 보이지 않는다면 (검색처럼) 계속 입력하세요. 라벨은 소문자를
사용하며, 보이는 매칭에 대해 다음에 입력할 법한 글자와는 절대 겹치지
않습니다.

**AI 코딩 에이전트와 함께 쓸 때** — 에이전트에 아래 내용을 붙여넣어
저장소를 넘기세요:

```text
Work in this repository. Read AGENTS.md at the repository root first and follow it.
```

### 입력 도중 언어 고정

입력 중에 `C-c` / `C-j` / `C-k` / `C-e`를 누르면 매칭을 중국어 / 일본어 /
한국어 / 영어로 고정하고 즉시 다시 계산합니다:

- `ti`는 중국어(梯/踢…)와 일본어(ち, 훈령식) 둘 다에 매칭되지만, `C-c`
  이후에는 중국어 읽기만 남고 ち는 더 이상 매칭되지 않습니다
- 고정 상태는 입력 문자열에 쌓입니다: **백스페이스로 마커를 지우면 고정이
  풀리며**, 다른 고정 키를 누르면 곧바로 전환됩니다
- 고정 중에도 리터럴 영어 매칭은 영향을 받지 않습니다
- 고정 키는 언어별로 `languages` 테이블에서 설정합니다(`force_key`, `false`로 끄기) — 아래 참고

### 언어 설정

각 언어는 `languages` 테이블로 독립적으로 설정합니다 — setup으로 전역적으로,
언어 코드 배열로 점프별로, 또는 필드 단위로 덮어쓰기:

```lua
require("flash-cjk").setup({
    languages = {
        zhcn = {enabled = true, scheme = "xiaohe", force_key = "<C-c>"},
        ja = {enabled = true, scheme = "roma", force_key = "<C-j>"},
        ko = {enabled = true, scheme = "roma", force_key = "<C-k>"},
        en = {enabled = true, force_key = "<C-e>"},  -- 스킴 개념 없음
    },
    alpha_mixing = true,
})

require("flash-cjk").jump({ "ja", "ko", "en" })  -- 이번 점프에서는 중국어 제외
require("flash-cjk").jump(nil, { languages = { ja = { force_key = "<C-d>" } } })
```

`scheme`은 중국어 `"xiaohe"`, 일본어와 한국어 `"roma"`를 받습니다(현재 유일한
스킴, 이후 확장 가능). `en`은 ASCII 리터럴 매칭으로 스킴 개념이 없으며, 주면
오류가 납니다. 항목은 `true`/`false` 약식 표기(`enabled` 상당)도 받습니다.
`setup`은 깊게 병합되어 지정하지 않은 필드는 현재 값을 유지합니다. 배열 없이
`jump()`를 호출하면 setup에서 켠 집합을 사용하고, 배열을 넘기면 그 점프의 활성
집합은 배열로만 완전히 결정됩니다(스킴은 각 언어의 기본값). setup 스위치보다
우선하며, 두 번째 인자는 flash 옵션을 그대로 전달하고 그 안의 `languages`는
그 점프에만 적용됩니다.

한 언어만 사용한다면 해당 언어 하나만 켜 두면 충분합니다. 참고 사항:

- `en`을 꺼도 숫자와 대문자는 여전히 문자 그대로 매칭되며, 해석할 수
  없는 입력(예: `n.`)은 리터럴 매칭으로 대체됩니다.
- 문장 부호는 언어 스위치를 따릅니다: `zhcn`을 끄면 `,`는 ，(전각 쉼표)가
  아니라 、(일본어)에 매칭됩니다. `。`는 중국어/일본어가 공유하므로 항상
  매칭되고, `-` → ー는 `ja`에 속합니다.
- `alpha_mixing = false` (성능): 리터럴 문자와 언어 세그먼트를 섞는 해석을
  버립니다(예: flash-zh에서 물려받은 일부 `nihao` 변형). 긴 3개 언어 입력에서
  최악의 경우 지연 시간이 40–60% 줄어드는 대신, 일부 혼합 체인에는 도달할 수
  없습니다.

### 매칭 규칙

- **중국어**: flypy(小鹤双拼，중국어 쌍병음 입력기)의 2키 코드와 병음 초성 —
  `ni` → 你, `r` → 日.
- **일본어**: Unicode Unihan의 한자 읽기(`kJapanese`/`On`/`Kun`, 약
  13,000자)를 최대 3글자의 로마지 접두사로 매칭(`n`/`ni`/`nic` 모두 日에
  적중). 가나는 해당 음절의 흔한 로마자 표기를 모두 매칭(`si`/`shi`,
  `tu`/`tsu`); 요음(拗音) 쌍은 하나의 단위로 매칭(`sha` → しゃ/シャ);
  `-`는 ー에, `[`/`]`는 「」『』에, `,`는 、에, `!`는 ！에 매칭됩니다.
- **한국어**: 음절을 프로그래밍 방식으로 자모(초성 × 중성 × 종성)로
  분해합니다 — 사전 데이터가 필요 없습니다. 로마자 표기: 개정 표기(2000)에
  흔한 매큔-라이샤워 표기(`kim`/`gim` → 김)를 더해 음절별 접두사로 매칭;
  두벌식 키도 함께 동작(`dkss` → 안녕, `gkrry` → 학교, `dkswek` → 앉다);
  경음(된소리) 자모는 Shift가 필요하니 로마자 표기(`kk`)를 대신 사용하세요;
  단일 모음 세그먼트는 일본어 모음처럼 입력 도중에도 동작합니다(`ai` →
  아이).

## Rust 가속 (선택 사항)

선택 사항인 네이티브 매처는 한 번 빌드되면 자동으로 켜집니다: 아래 벤치마크에서
최악의 경우를 평탄화합니다 — p95 꼬리 지연은 전체적으로 2.3×, 일본어/중국어 +
영어 조합에서는 최대 10× 개선됩니다. 또한 정규식
분기가 Vim의 컴파일 한계(E872)를 넘어선 패턴에서도 계속 동작합니다. 위 lazy
스펙의 `build =` 줄이 이를 처리하며, 수동 빌드는 다음과 같습니다:

```sh
cd rust && cargo build --release
```

바이너리가 없거나 빌드가 거듭 실패해도, 플러그인은 동일한 동작의 순수 Lua
vim-regex 경로로 투명하게 폴백합니다 — 항목별 교차 검증 스위트가 엄격하게
보장합니다. 자세한 내용과 측정치는 [rust/README.md](rust/README.md)를
참고하세요.

## 성능

<p align="center">
  <img
    src="assets/benchmark.svg"
    alt="벤치마크: vim-regex 경로와 네이티브 Rust 매처의, 완전한 15개 언어 조합 매트릭스에서 키 입력당 비용"
    width="720"
  />
</p>

실제 키 입력 경로에서 완전한 언어 조합 매트릭스로 측정했습니다: 네 가지 언어
코드 — `zhcn`(중국어), `ja`(일본어), `ko`(한국어), `en`(영어) — 의 단일어,
2중어, 3중어, 4중어 조합 전부, 총 15조합 × 70창 = 1,050개의 생성 창(각
20–60행). 각 행은 해당 행의 언어만 활성화하고, 창 텍스트는 그 언어들에서
표본 추출하며, 패턴은 바로 그 언어의 1–6개 타당한 키 입력입니다(`en`
단일어 행은 순수한 ASCII 단어). 시드는 고정입니다.

단일어 — 하나의 언어만 활성화:

| 창 내용 | vim-regex 평균 | Rust 평균 |  비율 | vim-regex p95 | Rust p95 |
| ------- | -------------: | --------: | ----: | ------------: | -------: |
| `ja`    |        0.85 ms |   8.57 ms | 0.10× |       2.74 ms |  9.43 ms |
| `zhcn`  |        0.22 ms |   8.89 ms | 0.03× |       0.51 ms |  9.36 ms |
| `en`    |        0.11 ms |   8.44 ms | 0.01× |       0.18 ms |  9.06 ms |
| `ko`    |        0.11 ms |   8.28 ms | 0.01× |       0.29 ms |  8.54 ms |

2중어 — 두 언어 활성화:

| 창 내용       | vim-regex 평균 | Rust 평균 |  비율 | vim-regex p95 | Rust p95 |
| ------------- | -------------: | --------: | ----: | ------------: | -------: |
| `ja` + `en`   |        29.6 ms |   9.82 ms |  3.0× |      138.3 ms |  14.2 ms |
| `ko` + `en`   |        4.96 ms |  10.64 ms | 0.47× |       36.4 ms |  24.5 ms |
| `zhcn` + `en` |        4.46 ms |   9.80 ms | 0.46× |       41.5 ms |  20.4 ms |
| `ja` + `ko`   |        1.35 ms |   8.48 ms | 0.16× |       4.19 ms |  8.87 ms |
| `zhcn` + `ja` |        1.03 ms |   8.85 ms | 0.12× |       4.70 ms |  9.34 ms |
| `zhcn` + `ko` |        0.31 ms |   8.98 ms | 0.03× |       0.65 ms |  9.71 ms |

3중어 — 세 언어 활성화:

| 창 내용              | vim-regex 평균 | Rust 평균 |  비율 | vim-regex p95 | Rust p95 |
| -------------------- | -------------: | --------: | ----: | ------------: | -------: |
| `zhcn` + `ja` + `en` |        28.9 ms |  11.17 ms |  2.6× |      245.3 ms |  24.6 ms |
| `ja` + `ko` + `en`   |        20.1 ms |  10.64 ms |  1.9× |      129.7 ms |  24.9 ms |
| `zhcn` + `ja` + `ko` |        8.48 ms |   9.36 ms | 0.91× |       46.8 ms |  11.2 ms |
| `zhcn` + `ko` + `en` |        5.69 ms |  10.69 ms | 0.53× |       32.6 ms |  19.5 ms |

4중어 — 네 언어 모두 활성화:

| 창 내용                     | vim-regex 평균 |   Rust 평균 |      비율 | vim-regex p95 |    Rust p95 |
| --------------------------- | -------------: | ----------: | --------: | ------------: | ----------: |
| `zhcn` + `ja` + `ko` + `en` |        16.8 ms |    11.44 ms |      1.5× |       95.1 ms |     23.9 ms |
| **전체(1,050개 창)**        |    **8.19 ms** | **9.60 ms** | **0.85×** |   **29.8 ms** | **13.0 ms** |

**방법론.** 각 케이스는 워밍업 1패스를 실행한 뒤 3회 측정 패스의 중앙값(`vim.uv.hrtime`)을
보고하며, 행은 그룹 내에서 vim-regex 평균 내림차순으로 정렬했습니다. 비율은
vim-regex 평균 ÷ Rust 평균이며, 1× 미만이면 순수 Lua 경로가 더 빠릅니다.
vim-regex 측정에는 실제 키 입력이 지불하는 모든 비용이 포함됩니다:
패턴 세그먼테이션, 분기 정규식 빌드, `vim.regex()` 컴파일, 보이는 모든 줄에
대한 매칭 스캔입니다. Rust 측정 역시 모든 비용을 포함합니다: `vim.system`
프로세스 생성과 JSON 왕복, 플러그인이 실제로 호출하는 방식 그대로입니다. 이번
실행에서는 1,050개 패턴 중 0개가 Vim NFA 엔진의 한계(E872)를 넘어섰습니다
— 조합별 언어 스위치가 분기를 작게 유지하기 때문입니다 — 만약 넘어서도 Rust
매처는 계속 동작합니다.

**해석 방법.** 단일어 행은 각 언어의 기준선입니다: 언어가 하나면 분기가
작아서 vim-regex 경로가 0.1–0.9 ms에 응답하는 반면, Rust 경로는 매 키 입력마다
고정 하한 비용(프로세스 생성 약 1.1 ms + 바이너리 시작 약 8.4 ms)을
지불합니다 — `en` 단일어 행은 사실상 이 spawn 오버헤드만을 보여줍니다. 주목할
것은 꼬리의 추세입니다: `en`을 `ja`나 `zhcn`에 섞으면 세그먼테이션 해석 수가
배가되어 vim-regex 비용은 평균 약 29 ms, p95는 138–245 ms(입력 중 체감되는
지연)에 도달하는 반면, Rust 경로는 모든 조합에서 8–25 ms의 평탄한 대역에
머뭅니다. 전체적으로 순수 Lua 경로는 중앙값에서 이기고(0.5 ms 대 8.9 ms —
짧은 접두사는 바이너리를 깨우지조차 않습니다), 네이티브 경로는 최악의 경우에서
이깁니다(p95 13.0 ms 대 29.8 ms, 가장 무거운 조합에서는 5–10×).

**시스템 영향.** 네이티브 매처는 키 입력마다, 보이는 창마다 수명이 짧은 프로세스를
하나 생성합니다(위 벤치마크는 단일 창 기준입니다). 각 호출은 약 9–12 ms의
실제 시간을 사용하며, 그 거의 전부가 프로세스 생성(약 1.1 ms)과 바이너리의
데이터 테이블 시작(약 8.4 ms)입니다. DP 매칭 자체는 서브밀리초~수 ms만
추가하므로, CPU/배터리 사용량은 타이핑 속도로 제한됩니다 — 대략 키 1회·창
1회당 작은 프로세스 시작 1회입니다. 바이너리는 약 1.8 MB이고 데이터 테이블을
정적으로 내장하며, 런타임 의존성이 없고 키 입력 동안만 메모리에 상주합니다.
바이너리가 없거나, 빌드에 실패하거나, 실행 중 반복적으로 실패하면 서킷 브레이커가 작동해
모든 키 입력이 vim-regex 경로로 투명하게 폴백합니다 — 매칭 결과는 동일하며
교차 검증 스위트가 보장합니다. 프로세스 생성이 비싸거나 제약받는 환경(샌드박스,
강화된 환경), 한 번에 한 언어로만 작업하거나 주로 1–2글자 접두사를 입력하는
사용 패턴(어차피 이쪽이 더 빠름)에서는 순수 vim-regex 경로(즉, 바이너리를
빌드하지 않음)를 선호하세요.

자신의 머신에서 재현하기:

```sh
cargo build --release --manifest-path rust/Cargo.toml
nvim -l benches/compare.lua # benches/results.json 생성
uv run benches/gen_svg.py   # assets/benchmark.svg 재생성
```

## 알려진 제한 사항

- macOS는 한글 파일명을 NFD(분해된 자모)로 저장합니다. 두 매칭 경로 모두
  NFC로 미리 조합된 음절을 대상으로 하므로, oil/netrw 파일명 버퍼 안에서
  점프할 때는 한글 파일명이 매칭되지 않습니다. 일반 코드 버퍼와 문서 버퍼는
  NFC이므로 영향을 받지 않습니다.

## 이어서 읽을 거리

| 목적                | 문서                                                                       |
| ------------------- | -------------------------------------------------------------------------- |
| 개발하고 검증하기   | [DEVELOPMENT.md](./DEVELOPMENT.md)                                         |
| 시스템 이해하기     | [ARCHITECTURE.md](./ARCHITECTURE.md)                                       |
| 변경 사항 기여하기  | [CONTRIBUTING.md](./CONTRIBUTING.md)                                       |
| 에이전트에게 넘기기 | [AGENTS.md](./AGENTS.md)                                                   |
| 네이티브 매처 설계  | [rust/README.md](./rust/README.md)                                         |
| 다른 언어로 읽기    | [简体中文](README.zh.md) · [日本語](README.ja.md) · [한국어](README.ko.md) |

## 환경 요구 사항

- [flash.nvim](https://github.com/folke/flash.nvim)과 함께 쓰는 Neovim ≥ 0.10
- 네이티브 가속기용 선택 사항 Rust ≥ 1.97(cargo) — 없어도 모든 기능이
  동작합니다
- 개발 도구 체인: mise로 관리([DEVELOPMENT.md](./DEVELOPMENT.md) 참고)

## 라이선스

MIT — [LICENSE](./LICENSE)를 참고하세요. 데이터는
[Unicode Unihan Database](https://www.unicode.org/)에서 파생되었습니다(Unicode
License). [flash-zh.nvim](https://github.com/rainzm/flash-zh.nvim)과
[hop-zh-by-flypy](https://github.com/zzhirong/hop-zh-by-flypy)에 감사드립니다.
