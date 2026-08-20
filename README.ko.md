<div align="center">

# flash-cjk.nvim

IME를 전환하지 않고도 병음·로마지·로마자 표기를 입력해 Neovim 안의 간체
중국어·일본어·한국어 문자 어디로든 점프하세요.
[flash.nvim](https://github.com/folke/flash.nvim)을 기반으로 하며,
[flash-zh.nvim](https://github.com/rainzm/flash-zh.nvim)에서 포크되었습니다.

[English](README.md) · [简体中文](README.zh.md) · [日本語](README.ja.md) · [한국어](README.ko.md)

[![Validate](https://github.com/fang2hou/flash-cjk.nvim/actions/workflows/validate.yml/badge.svg)](https://github.com/fang2hou/flash-cjk.nvim/actions/workflows/validate.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](./LICENSE)

</div>

점프하려는 한중일 텍스트를 찾으려고 한중일 텍스트를 입력하는 것은, 동작
한가운데서 IME와 씨름하는 일입니다. flash-cjk는 손을 ASCII 안에 그대로
둡니다: `ni`는 你 / 日 / に / ニ에 닿고, `r`은 병음 초성으로 日을 찾으며,
`dkss`는 두벌식 키로 안녕에 닿습니다 — 나머지 평범한 영문자는
flash.nvim과 똑같이 문자 그대로 매칭됩니다.

- 다루는 범위: 간체 중국어 병음(샤오헤 쌍병음(小鹤双拼)과 초성), 일본어
  로마지(한자 읽기와 가나, 헵번식과 훈령식), 한국어(로마자 표기법(RR)과
  두벌식 키 시퀀스), 리터럴 ASCII — 모두 동시에 켤 수 있고 각각 독립적으로
  켜고 끌 수 있습니다
- 다루지 않는 범위: flash.nvim 자체 기능 대체(treesitter 점프, remote
  등); IME 연동; NFD 형태의 한글 파일명(기능 섹션의 알려진 제한 사항
  참고)
- 상태: 활발히 개발 중

## 🚀 사용법

[flash.nvim](https://github.com/folke/flash.nvim)과 Neovim ≥ 0.10이
필요합니다. [lazy.nvim](https://github.com/folke/nvim-lazy)으로 설치하세요:

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

lazy.nvim을 쓰지 않는다면 위 `opts`와 같은 옵션으로
`require("flash-cjk").setup({ ... })`를 직접 호출하세요.

`s`를 누르고, 입력하고, 점프하세요 — flash.nvim과 같은 흐름입니다. 대상에
아직 라벨이 보이지 않는다면 (검색처럼) 계속 입력하세요. 라벨은 소문자를
사용하며, 보이는 매칭에 대해 다음에 입력할 법한 글자와는 절대 겹치지
않습니다.

**AI 코딩 에이전트와 함께 쓸 때** — 에이전트에 아래 내용을 붙여넣어
저장소를 넘기세요:

```text
Work in this repository. Read AGENTS.md at the repository root first and follow it.
```

**플러그인을 개발하거나 벤치마크하려면** macOS 또는 Linux에서
[mise](https://mise.jdx.dev/)가 필요합니다:

```bash
mise install
mise run test
```

`mise run`은 나머지 모든 작업(`check`, `e2e`, `codegen`, `format`)을
보여줍니다. [DEVELOPMENT.md](./DEVELOPMENT.md)를 참고하세요.

<details>
<summary>Rust 가속기: 필요한 때와 필요 없는 때</summary>

위의 `build =` 줄은 cargo가 있을 때만 선택적 네이티브 매처를 빌드합니다.
수동 빌드는 `cd rust && cargo build --release`입니다. Rust가 꼭 필요한
것은 아닙니다: 바이너리가 없으면 플러그인은 조용히 vim-regex 경로를
사용하며 결과는 동일합니다(교차 검증으로 보장). 샌드박스나 제한된
환경에서는 `build =` 줄을 삭제하세요 — 순수 Lua 경로는 컴파일러가 필요
없고 프로세스도 시작하지 않습니다.

</details>

## 💡 개념

- **해석** — 모든 키 입력열은 리터럴 영문자와 언어 코드(병음, 로마지,
  로마자 표기)로 분할되며, 같은 입력의 그럴듯한 읽기는 모두 한꺼번에 도달
  가능한 상태로 남습니다. `ni`는 간체 중국어(你)와 일본어(日 / に / ニ)
  둘 다에 매칭됩니다.
- **언어 고정** — 입력 중에 `C-c` / `C-j` / `C-k` / `C-e`를 누르면 매칭을
  간체 중국어 / 일본어 / 한국어 / 영어로 고정하고 즉시 다시 계산합니다:
  `C-c` 이후에는 간체 중국어 읽기만 남고 ち는 더 이상 매칭되지 않습니다.
  고정은 입력 문자열에 쌓이므로 **백스페이스로 마커를 지우면 고정이
  풀리며**, 다른 고정 키를 누르면 곧바로 전환됩니다. 고정 키는 언어별로
  설정할 수 있습니다(`force_key`, `false`로 끄기).
- **혼합 입력** — 키 입력열은 일부는 리터럴로, 일부는 언어 코드로 읽을 수
  있습니다. `nn`을 입력하면 `日n`에 도달합니다(로마지 `n` + 리터럴 `n`).
  거울형인 `n日`은 맨 앞 리터럴이 항상 허용되므로 모든 모드에서
  매칭됩니다. `mixed_input = false`로 끄면 반대 형태(언어 다음 리터럴)만
  버려지고 긴 3개 언어 입력의 최악 경우 지연 시간이 40–60% 줄어듭니다 —
  긴 입력이 눈에 띄게 느려지지 않는 한 기본값을 유지하세요.
- **점프별 언어 집합** — 각 언어는 `languages` 테이블로 독립적으로
  설정합니다(전역은 `setup`으로, 점프별로는 `jump({ "ja", "ko", "en" })`
  처럼 — 이 점프에서는 간체 중국어가 매칭되지 않습니다). `setup`은 깊게
  병합되며 `true`/`false` 약식 표기는 `enabled`를 켜고 끕니다. 문장 부호는
  스위치를 따라갑니다: `zhcn`을 끄면 `,`는 ，(전각 쉼표)가 아니라
  、(일본어)에 매칭됩니다.

## ✨ 기능

- **간체 중국어(`zhcn`)** — 샤오헤 쌍병음(小鹤双拼) 2키 코드나 병음 초성을
  입력하세요: `ni` → 你, `r` → 日. 모든 한자는 자기 2키 코드로 도달할 수
  있고, 한 글자만 입력하면 그 글자로 병음이 시작하는 한자 전부에
  매칭됩니다. 스킴: `"xiaohe"`(현재 유일하며 이후 확장 가능).
- **일본어(`ja`)** — 로마지 매칭: `ni`는 日에, `ti`는 ち(훈령식)에
  적중합니다. Unicode Unihan의 한자 읽기(약 13,000자)는 최대 3글자 로마지
  접두사로 매칭되고(`n`/`ni`/`nic` 모두 日에 적중), 가나는 해당 음절의
  흔한 로마자 표기를 모두 매칭하며(`si`/`shi`, `tu`/`tsu`), 요음(拗音)
  쌍은 하나의 단위로 매칭됩니다(`sha` → しゃ/シャ). `-`는 장음 ー에,
  `[`/`]`는 「」『』에, `,`는 、에, `!`는 ！에 매칭됩니다.
- **한국어(`ko`)** — 두벌식(한국 표준 자판) 시퀀스: `dks` → 안, `gkrry` →
  학교, `dkswek` → 앉다. 또는 로마자 표기: 로마자 표기법(RR, Revised
  Romanization of Korean)과 흔한 매큔-라이샤워 표기(`kim`/`gim` → 김)를
  음절별 접두사로 매칭합니다. 음절은 규칙에 따라 자모로 분해됩니다 — 사전
  데이터가 필요 없습니다. 경음(된소리) 자모는 두벌식에서 Shift가 필요하니
  로마자 표기(`kk`)를 대신 사용하세요. 단일 모음 세그먼트는 일본어 모음처럼
  입력 도중에도 동작합니다(`ai` → 아이).
- **영어(`en`)** — 평범한 ASCII는 한 글자씩 글자 그대로, flash.nvim 자체
  검색과 똑같이 매칭됩니다: 코드 식별자는 어떤 언어 해석 없이도 도달할 수
  있습니다. `en`을 꺼도 숫자와 대문자는 여전히 문자 그대로 매칭되며,
  활성화된 언어 어디로도 해석할 수 없는 입력(예: `n.`)은 리터럴 매칭으로
  대체됩니다.
- **우선순위 라벨** — `priority = { "ja", "zhcn" }`은 라벨 할당 순서를
  정합니다: 목록 앞쪽 언어로 도달 가능한 매칭이 가장 빠른 라벨부터 받으므로
  주 언어 대상은 가장 적은 라벨 키로 이동할 수 있습니다. 매칭 집합과 점프
  동작은 변하지 않으며, 미설정 시 단순 위치 순서를 유지합니다.

알려진 제한 사항: macOS는 한글 파일명을 NFD(분해된 자모)로 저장합니다.
두 매칭 경로 모두 NFC로 미리 조합된 음절을 대상으로 하므로, oil/netrw
파일명 버퍼 안에서 점프할 때는 한글 파일명이 매칭되지 않습니다. 일반 코드
버퍼와 문서 버퍼는 NFC이므로 영향을 받지 않습니다.

## ⚡ 성능

짧은 접두사(1–2글자)는 내장 vim-regex 경로에서 중앙값 약 0.5 ms에
응답합니다(단일 언어 활성화 시 0.1–0.9 ms). 무거운 쪽은 이 경로에서의 긴
3개 언어 입력입니다: 가장 무거운 조합에서 평균 최대 약 30 ms, p95는
134–243 ms에 도달합니다. 선택 사항인 네이티브 매처는 최악의 경우를
평탄화합니다 — 평균은 전체적으로 8.5×, p95 꼬리는 6.7×(가장 무거운
조합에서 최대 27×) 낮아지며 — 정규식 분기가 더는 Vim에서 컴파일되지 않는
패턴에서도 계속 동작합니다(E872). 한 번 빌드되면 자동으로 켜집니다.

<p align="center">
  <img
    src="assets/benchmark.svg"
    alt="벤치마크: 전체 15조합 언어 매트릭스에서 vim-regex 경로와 상주 서버 위 네이티브 Rust 매처의 키 입력당 비용"
    width="720"
  />
</p>

전체 언어 조합 매트릭스에서 실제 키 입력 경로를 측정했습니다: 4개 언어
코드 — `zhcn`(간체 중국어), `ja`(일본어), `ko`(한국어), `en`(영어) — 의
모든 단일·2개·3개·4개 조합, 15조합 × 70윈도우 = 1,050개의 20–60행 생성
윈도우. 각 행은 해당 행의 언어만 활성화하고 그 언어들에서 윈도우 텍스트를
샘플링하며, 그 언어에 맞는 1–6 키 입력을 타이핑합니다(`en` 단독 행은 순수
ASCII 단어). 시드는 고정되어 재현 가능합니다.

**Rust(server)**는 실제 키 입력이 사용하는 네이티브 경로입니다: 키 입력마다
상주 매처 서버로 요청 하나를 보냅니다(아래 참고).

단일 언어 — 하나만 활성화:

| 윈도우 언어 | vim-regex 평균 | Rust server |  비율 | vim-regex p95 | server p95 |
| ----------- | -------------: | ----------: | ----: | ------------: | ---------: |
| `ja`        |        1.22 ms |     0.16 ms |  7.8× |        4.6 ms |    0.40 ms |
| `zhcn`      |        0.20 ms |     0.09 ms |  2.2× |        0.5 ms |    0.14 ms |
| `en`        |        0.08 ms |     0.11 ms | 0.75× |        0.1 ms |    0.14 ms |
| `ko`        |        0.08 ms |     0.10 ms | 0.81× |        0.2 ms |    0.16 ms |

두 언어 — 둘만 활성화:

| 윈도우 언어   | vim-regex 평균 | Rust server |  비율 | vim-regex p95 | server p95 |
| ------------- | -------------: | ----------: | ----: | ------------: | ---------: |
| `ja` + `en`   |       29.99 ms |     1.35 ms | 22.2× |      134.1 ms |    5.00 ms |
| `ko` + `en`   |        4.94 ms |     2.13 ms |  2.3× |       35.2 ms |   16.60 ms |
| `zhcn` + `en` |        4.43 ms |     1.23 ms |  3.6× |       44.8 ms |   11.94 ms |
| `ja` + `ko`   |        1.49 ms |     0.18 ms |  8.2× |        4.4 ms |    0.50 ms |
| `zhcn` + `ja` |        1.04 ms |     0.16 ms |  6.4× |        3.6 ms |    0.34 ms |
| `zhcn` + `ko` |        0.24 ms |     0.13 ms |  1.8× |        0.6 ms |    0.25 ms |

세 언어 — 셋만 활성화:

| 윈도우 언어          | vim-regex 평균 | Rust server |  비율 | vim-regex p95 | server p95 |
| -------------------- | -------------: | ----------: | ----: | ------------: | ---------: |
| `zhcn` + `ja` + `en` |       29.12 ms |     2.43 ms | 12.0× |      243.4 ms |   14.79 ms |
| `ja` + `ko` + `en`   |       19.48 ms |     2.10 ms |  9.3× |      129.7 ms |   15.47 ms |
| `zhcn` + `ja` + `ko` |        9.07 ms |     0.67 ms | 13.6× |       47.5 ms |    2.40 ms |
| `zhcn` + `ko` + `en` |        5.80 ms |     1.83 ms |  3.2× |       32.9 ms |   10.88 ms |

네 언어 모두 활성화:

| 윈도우 언어                 | vim-regex 평균 | Rust server |     비율 | vim-regex p95 |  server p95 |
| --------------------------- | -------------: | ----------: | -------: | ------------: | ----------: |
| `zhcn` + `ja` + `ko` + `en` |       16.26 ms |     1.90 ms |     8.6× |       95.0 ms |    14.04 ms |
| **전체(1,050 윈도우)**      |    **8.23 ms** | **0.97 ms** | **8.5×** |   **29.1 ms** | **4.35 ms** |

**방법론.** 각 케이스는 워밍업 1회 후 3회 실측의 중앙값(`vim.uv.hrtime`)을
사용합니다. 행은 그룹 내에서 vim-regex 평균 순으로 정렬됩니다. 비율은
vim-regex 평균 ÷ Rust server 평균이며, 1× 미만이면 순수 Lua 경로가 더
빠릅니다. vim-regex 측정은 실제 키 입력이 지불하는 모든 비용(패턴 분할,
대안 분기 구성, `vim.regex()` 컴파일, 보이는 모든 행 스캔)을 포함합니다.
Rust 측정은 상주 서버로 보내는 UDS 요청 하나 — 실제 키 입력과 완전히 같은
전송입니다. 이번 실행에서는 1,050개 패턴 중 0개가 Vim의 NFA 캡처 그룹
한계(E872)에 도달했지만, 도달해도 Rust 매처는 계속 동작합니다.

**해석 방법.** 상주 서버는 프로세스 생성과 데이터 테이블 구성을 자기 시작
시 한 번만 지불하고 이후 0.09–2.5 ms의 평탄한 구간에서 응답합니다. 15개
카테고리 중 13개가 Rust 우위이고 나머지 2개(`en`/`ko` 단독)도 0.08 대
0.10–0.11 ms로 어느 쪽이든 0.2 ms 미만입니다. 중요한 것은 꼬리입니다. 가장
무거운 조합(`ja`+`en`, `zhcn`+`ja`+`en`)의 p95는 vim-regex의 134–243 ms에서
5.0–14.8 ms로, 전체 p95도 29.1 ms에서 4.4 ms로 내려갑니다.

<details>
<summary>백그라운드 서비스(Unix, 설정 불필요)</summary>

바이너리가 있으면 플러그인은 사용자별로 매처 서버 하나를 투명하게
유지합니다:

- **라이프사이클**: 서버는 Neovim 인스턴스가 유휴 세션 연결 하나를 열고
  있는 동안에만 그 인스턴스를 등록합니다. Neovim을 종료하거나(또는
  `kill -9`로 죽이면) 등록이 즉시 해제되고, 어떤 인스턴스도 2초간
  (`FLASH_CJK_SERVER_GRACE_MS`) 연결하지 않으면 서버는 자신의 소켓을
  지우고 종료합니다. 마지막 인스턴스가 나가면 서버도 함께 사라집니다 —
  폴링도, 데몬 관리도, 설정도 없습니다.
- **메모리**: 상주 프로세스는 하나뿐(약 12.4 MB RSS)이며 최소 한 개의
  Neovim 인스턴스가 사용하는 동안에만 존재하고, 여기에 키 입력당 약
  0.04 ms의 유닉스 도메인 소켓 왕복이 더해집니다. CPU/배터리 사용량은
  프로세스를 얼마나 자주 띄우는지가 아니라 얼마나 많이 입력하는지를
  따라갑니다.
- **자동 폴백**: 전송 계층의 일시적 실패(타임아웃, 크래시)는 해당 키
  입력을 spawn 전송으로 떨어뜨리고 서버를 비동기로 되살립니다. 실패가
  반복되면 서킷 브레이커가 동작해 vim-regex 경로로 내려갑니다. Windows와
  지나치게 긴 소켓 경로(`sun_path` 한계)는 spawn 전송을 유지합니다.

바이너리는 약 1.8 MB이고 데이터 테이블을 정적으로 내장하며 런타임 의존성이
없습니다. 상주 메모리가 부족하거나 프로세스 시작이 제한되는 환경에서는 순수
vim-regex 경로(즉, 단순히 바이너리를 빌드하지 않는 것)를 권장합니다.

</details>

자신의 기기에서 재현하기:

```sh
cargo build --release --manifest-path rust/Cargo.toml
nvim -l benches/compare.lua # writes benches/results.json
uv run benches/gen_svg.py   # regenerates assets/benchmark.svg
```

## 📚 이어서 읽을 거리

| 목적                | 문서                                                                       |
| ------------------- | -------------------------------------------------------------------------- |
| 시스템 이해하기     | [ARCHITECTURE.md](./ARCHITECTURE.md)                                       |
| 개발하고 검증하기   | [DEVELOPMENT.md](./DEVELOPMENT.md)                                         |
| 변경 사항 기여하기  | [CONTRIBUTING.md](./CONTRIBUTING.md)                                       |
| 에이전트에게 넘기기 | [AGENTS.md](./AGENTS.md)                                                   |
| 네이티브 매처 설계  | [rust/README.md](./rust/README.md)                                         |
| 다른 언어로 읽기    | [简体中文](README.zh.md) · [日本語](README.ja.md) · [한국어](README.ko.md) |

## 📄 라이선스

MIT — [LICENSE](./LICENSE)를 참고하세요. 데이터는
[Unicode Unihan Database](https://www.unicode.org/)에서 파생되었습니다(Unicode
License). [flash-zh.nvim](https://github.com/rainzm/flash-zh.nvim)과
[hop-zh-by-flypy](https://github.com/zzhirong/hop-zh-by-flypy)에 감사드립니다.
