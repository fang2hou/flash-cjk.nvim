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
- 키는 설정으로 바꿀 수 있습니다(끄려면 `false`):

```lua
require("flash-cjk").setup({
    force_keys = {
        cn = "<C-c>",
        jp = "<C-j>",
        ko = "<C-k>",
        en = "<C-e>",
    },
})
```

### 언어 스위치

각 매처는 서로 독립적으로 켜고 끌 수 있습니다 — setup으로 전역적으로, 또는 언어 코드 배열로 점프별로:

```lua
require("flash-cjk").setup({
    cn = "xiaohe",   -- 중국어 병음. true / false 또는 스킴 이름
    jp = "roma",     -- 일본어 로마지(한자 읽기 + 가나)
    ko = "roma",     -- 한국어(로마자 표기 + 두벌식 키)
    en = true,       -- 리터럴 ASCII 문자(일반 flash.nvim 동작)
    alpha_mixing = true,
})

require("flash-cjk").jump({ "jp", "ko", "en" })  -- 이번 점프에서는 중국어 제외
```

`cn`/`jp`/`ko`는 `true`(기본 스킴), `false`(끄기) 또는 스킴 이름 문자열을 받습니다 — 중국어는 `"xiaohe"`, 일본어와 한국어는 `"roma"`(현재 유일한 스킴, 이후 확장 가능). 배열 없이 `jump()`를 호출하면 setup에서 켠 집합을 사용하고, 배열을 넘기면 그 점프의 활성 집합은 배열로만 완전히 결정됩니다(`"kr"`은 `"ko"`의 별칭). setup 스위치보다 우선하며, 두 번째 인자는 flash 옵션을 그대로 전달합니다: `jump(nil, { force_keys = { cn = "<C-d>" } })`.

한 언어만 사용한다면 해당 스위치 하나만 켜 두면 됩니다. 참고 사항:

- `en`을 꺼도 숫자와 대문자는 여전히 문자 그대로 매칭되며, 해석할 수
  없는 입력(예: `n.`)은 리터럴 매칭으로 대체됩니다.
- 문장 부호는 언어 스위치를 따릅니다: `cn`을 끄면 `,`는 ，(전각 쉼표)가
  아니라 、(일본어)에 매칭됩니다. `。`는 중국어/일본어가 공유하므로 항상
  매칭되고, `-` → ー는 `jp`에 속합니다.
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
  아이).\n\n## Rust 가속 (선택 사항)

선택 사항인 네이티브 매처는 한 번 빌드되면 자동으로 켜집니다: 긴 입력에서
키 입력당 지연 시간이 55–80 ms에서 1–3 ms로 떨어집니다(vim-regex 경로 대비
3.8배–76배). 위 lazy 스펙의 `build =` 줄이 이를 처리하며, 수동 빌드는
다음과 같습니다:

```sh
cd rust && cargo build --release
```

바이너리가 없거나 빌드가 거듭 실패해도, 플러그인은 동일한 동작의 순수 Lua
vim-regex 경로로 투명하게 폴백합니다 — 항목별 교차 검증 스위트가 엄격하게
보장합니다. 자세한 내용과 측정치는 [rust/README.md](rust/README.md)를
참고하세요.

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
