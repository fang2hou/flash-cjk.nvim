#!/usr/bin/env python3
# /// script
# requires-python = ">=3.12"
# dependencies = []
# ///
"""Generate lua/flash-cjk/jp_data.lua from the Unicode Unihan database.

Data sources (per kanji):
  - kJapanese: readings in kana, most complete (preferred)
  - kJapaneseOn / kJapaneseKun: readings in Hepburn romaji.
    Their union selects the kanji universe (JIS-representable set)
    and is used as fallback when kJapanese is missing.

The generated tables drive two independent lookups:
  - p1/p2/p3: romaji prefix (1/2/3 letters) -> vim regex fragment,
    used by the search parser. p3 fragments may match two characters
    at once (youon combos like しゃ = "sha").
  - readings: character -> romaji variants, used by the labeler to
    predict the next likely input letter of a match.

Usage:
  uv run scripts/gen_jp_data.py [Unihan_Readings.txt]

With no argument the script downloads Unihan.zip from unicode.org.
"""

from __future__ import annotations

import io
import re
import sys
import urllib.request
import zipfile
from pathlib import Path

UNIHAN_VERSION = "16.0.0"
UNIHAN_URL = f"https://www.unicode.org/Public/{UNIHAN_VERSION}/ucd/Unihan.zip"
OUT = Path(__file__).resolve().parent.parent / "lua" / "flash-cjk" / "jp_data.lua"

MAX_READINGS_PER_KANJI = 12
MAX_VARIANTS_PER_READING = 8

# ---------------------------------------------------------------------------
# kana <-> romaji

# (hiragana, katakana, canonical romaji)
_KANA = [
    ("あ", "ア", "a"), ("い", "イ", "i"), ("う", "ウ", "u"), ("え", "エ", "e"), ("お", "オ", "o"),
    ("か", "カ", "ka"), ("き", "キ", "ki"), ("く", "ク", "ku"), ("け", "ケ", "ke"), ("こ", "コ", "ko"),
    ("が", "ガ", "ga"), ("ぎ", "ギ", "gi"), ("ぐ", "グ", "gu"), ("げ", "ゲ", "ge"), ("ご", "ゴ", "go"),
    ("さ", "サ", "sa"), ("し", "シ", "shi"), ("す", "ス", "su"), ("せ", "セ", "se"), ("そ", "ソ", "so"),
    ("ざ", "ザ", "za"), ("じ", "ジ", "ji"), ("ず", "ズ", "zu"), ("ぜ", "ゼ", "ze"), ("ぞ", "ゾ", "zo"),
    ("た", "タ", "ta"), ("ち", "チ", "chi"), ("つ", "ツ", "tsu"), ("て", "テ", "te"), ("と", "ト", "to"),
    ("だ", "ダ", "da"), ("ぢ", "ヂ", "di"), ("づ", "ヅ", "du"), ("で", "デ", "de"), ("ど", "ド", "do"),
    ("な", "ナ", "na"), ("に", "ニ", "ni"), ("ぬ", "ヌ", "nu"), ("ね", "ネ", "ne"), ("の", "ノ", "no"),
    ("は", "ハ", "ha"), ("ひ", "ヒ", "hi"), ("ふ", "フ", "fu"), ("へ", "ヘ", "he"), ("ほ", "ホ", "ho"),
    ("ば", "バ", "ba"), ("び", "ビ", "bi"), ("ぶ", "ブ", "bu"), ("べ", "ベ", "be"), ("ぼ", "ボ", "bo"),
    ("ぱ", "パ", "pa"), ("ぴ", "ピ", "pi"), ("ぷ", "プ", "pu"), ("ぺ", "ペ", "pe"), ("ぽ", "ポ", "po"),
    ("ま", "マ", "ma"), ("み", "ミ", "mi"), ("む", "ム", "mu"), ("め", "メ", "me"), ("も", "モ", "mo"),
    ("や", "ヤ", "ya"), ("ゆ", "ユ", "yu"), ("よ", "ヨ", "yo"),
    ("ら", "ラ", "ra"), ("り", "リ", "ri"), ("る", "ル", "ru"), ("れ", "レ", "re"), ("ろ", "ロ", "ro"),
    ("わ", "ワ", "wa"), ("ゐ", "ヰ", "wi"), ("ゑ", "ヱ", "we"), ("を", "ヲ", "wo"), ("ん", "ン", "n"),
    ("ゔ", "ヴ", "vu"), ("ヷ", "ヷ", "va"), ("ヸ", "ヸ", "vi"), ("ヹ", "ヹ", "ve"), ("ヺ", "ヺ", "vo"),
    ("ぁ", "ァ", "xa"), ("ぃ", "ィ", "xi"), ("ぅ", "ゥ", "xu"), ("ぇ", "ェ", "xe"), ("ぉ", "ォ", "xo"),
    ("ゃ", "ャ", "xya"), ("ゅ", "ュ", "xyu"), ("ょ", "ョ", "xyo"), ("っ", "ッ", "xtu"),
]

# small y-kana (youon second half), both scripts, keyed by the vowel they add
SMALL_Y = {"ゃ": "a", "ゅ": "u", "ょ": "o", "ャ": "a", "ュ": "u", "ョ": "o"}

# Hepburn spelling -> alternative spellings (kunrei-shiki and common IME forms)
_ROMA_ALIASES = {
    "shi": ("si", "ci"),
    "chi": ("ti",),
    "tsu": ("tu",),
    "ji": ("zi",),
    "fu": ("hu",),
    "sha": ("sya",),
    "shu": ("syu",),
    "sho": ("syo",),
    "cha": ("tya", "cya"),
    "chu": ("tyu", "cyu"),
    "cho": ("tyo", "cyo"),
    "ja": ("zya", "jya"),
    "ju": ("zyu", "jyu"),
    "jo": ("zyo", "jyo"),
    "di": ("ji", "dzi"),
    "du": ("zu",),
}
_X_ALIASES = {"xa": "la", "xi": "li", "xu": "lu", "xe": "le", "xo": "lo",
              "xya": "lya", "xyu": "lyu", "xyo": "lyo", "xtu": "ltu"}

KANA_ROMA: dict[str, str] = {}
KANA_SET: set[str] = set()
for _h, _k, _r in _KANA:
    KANA_ROMA[_h] = _r
    KANA_ROMA[_k] = _r
    KANA_SET.add(_h)
    KANA_SET.add(_k)


def roma_variants(roma: str) -> list[str]:
    """All accepted spellings of one romaji syllable."""
    out = {roma}
    for src, aliases in _ROMA_ALIASES.items():
        if src in roma:
            for v in list(out):
                for a in aliases:
                    out.add(v.replace(src, a))
    if roma in _X_ALIASES:
        out.add(_X_ALIASES[roma])
    if roma == "wo":
        out.add("o")
    if roma == "n":
        out.add("nn")
    return sorted(out, key=lambda s: (s != roma, s))
def merge_youon(base: str, vowel: str) -> str:
    """き+ゃ -> kya, し+ゃ -> sha, ち+ゃ -> cha, じ+ゃ -> ja, ぢ+ゃ -> dya."""
    if base in ("shi", "chi", "ji"):
        return base[:-1] + vowel
    return base[:-1] + "y" + vowel


def kana_to_romaji(text: str) -> list[str]:
    """Convert one kana reading into all accepted romaji spellings."""
    chars = list(text)
    results: list[str] = [""]
    i = 0
    while i < len(chars):
        ch = chars[i]
        base = KANA_ROMA.get(ch)
        if base is None:
            if ch == "ー":
                # chōonpu: extend the previous vowel
                results = [r + (r[-1] if r and r[-1] in "aiueo" else "u") for r in results]
            else:
                results = [r + ch for r in results]  # non-kana: keep literal
            i += 1
            continue

        variants: list[str]
        nxt = chars[i + 1] if i + 1 < len(chars) else ""

        if ch in SMALL_Y and results and results[0]:
            # standalone small y-kana: direct-input spelling only
            variants = roma_variants(base)
        elif nxt in SMALL_Y and len(base) >= 2 and base.endswith("i"):
            # youon: merge with the following small y-kana (き+ゃ -> kya)
            variants = roma_variants(merge_youon(base, SMALL_Y[nxt]))
            i += 1
        else:
            variants = roma_variants(base)

        if ch in ("っ", "ッ"):
            # sokuon: emit the doubled initial consonant of the next kana
            after = chars[i + 1] if i + 1 < len(chars) else ""
            after_roma = KANA_ROMA.get(after, "")
            if after_roma and after_roma[0] not in "aiueoynw":
                results = [r + after_roma[0] for r in results]
                i += 1
                continue
            variants = roma_variants("xtu")

        results = [r + v for r in results for v in variants]
        if len(results) > MAX_VARIANTS_PER_READING:
            results = sorted(set(results))[:MAX_VARIANTS_PER_READING]
        i += 1
    return sorted(set(results))


def normalize_romaji_reading(value: str) -> list[str]:
    """On/Kun romaji field -> variant list. Keeps the stem before '.'."""
    out: set[str] = set()
    for token in value.split():
        stem = token.split(".")[0].lower()
        stem = re.sub(r"[^a-z]", "", stem)
        if not stem:
            continue
        if len(stem) <= 4:
            out.update(roma_variants(stem))
        else:
            out.add(stem)
    return sorted(out)



# ---------------------------------------------------------------------------
# Unihan parsing

def parse_unihan(path: Path) -> tuple[dict[str, str], dict[str, list[str]]]:
    kjapanese: dict[str, str] = {}
    onkun: dict[str, list[str]] = {}
    field_re = re.compile(r"^(U\+[0-9A-F]+)\t(kJapanese|kJapaneseOn|kJapaneseKun)\t(.+)$")
    for line in path.read_text(encoding="utf-8").splitlines():
        m = field_re.match(line)
        if not m:
            continue
        code, field, value = m.groups()
        if field == "kJapanese":
            kjapanese[code] = value.strip()
        else:
            onkun.setdefault(code, []).append(value.strip())
    return kjapanese, onkun


def code_to_char(code: str) -> str:
    return chr(int(code[2:], 16))


def get_unihan() -> Path:
    if len(sys.argv) > 1:
        return Path(sys.argv[1])
    cache = Path("/tmp/flash-cjk-unihan/Unihan_Readings.txt")
    if not cache.exists():
        print(f"downloading {UNIHAN_URL}")
        data = urllib.request.urlopen(UNIHAN_URL).read()
        cache.parent.mkdir(parents=True, exist_ok=True)
        with zipfile.ZipFile(io.BytesIO(data)) as z:
            z.extract("Unihan_Readings.txt", cache.parent)
    return cache


# ---------------------------------------------------------------------------
# table building

def build():
    readings: dict[str, list[str]] = {}          # char -> romaji variants
    singles: dict[int, dict[str, set[str]]] = {1: {}, 2: {}, 3: {}}
    combos: dict[str, set[str]] = {}             # 3-letter prefix -> 2-char atoms

    def add_char(char: str, romas: list[str]) -> None:
        # insertion order keeps canonical spellings first (roma_variants
        # sorts canonical first; Unihan lists common readings first)
        romas = list(dict.fromkeys(romas))
        if not romas:
            return
        merged = readings.setdefault(char, [])
        for roma in romas:
            if roma not in merged:
                merged.append(roma)
        for roma in romas:
            singles[1].setdefault(roma[:1], set()).add(char)
            if len(roma) >= 2:
                singles[2].setdefault(roma[:2], set()).add(char)
            if len(roma) >= 3:
                singles[3].setdefault(roma[:3], set()).add(char)

    # --- kana ---
    n_kana = 0
    for h, k, r in _KANA:
        n_kana += 2
        add_char(h, roma_variants(r))
        add_char(k, roma_variants(r))
        # youon combos: consonant-i base + small y -> two-character atoms
        if len(r) >= 2 and r.endswith("i"):
            for small_h, vowel in [("ゃ", "a"), ("ゅ", "u"), ("ょ", "o")]:
                merged = merge_youon(r, vowel)
                kata_small = {"a": "ャ", "u": "ュ", "o": "ョ"}[vowel]
                for variant in roma_variants(merged):
                    if len(variant) == 3:
                        combos.setdefault(variant, set()).update({h + small_h, k + kata_small})


    # --- kanji ---
    kjapanese, onkun = parse_unihan(get_unihan())
    n_fallback = 0
    for code in onkun:
        kanji = code_to_char(code)
        romas: set[str] = set()
        if code in kjapanese:
            for reading in kjapanese[code].split():
                romas.update(kana_to_romaji(reading))
        else:
            n_fallback += 1
            for value in onkun[code]:
                romas.update(normalize_romaji_reading(value))
        add_char(kanji, sorted(romas))
    readings = {c: sorted(set(v), key=lambda s: (len(s), s))[:MAX_READINGS_PER_KANJI] for c, v in readings.items()}

    return readings, singles, combos, n_kana, n_fallback, len(onkun)


# ---------------------------------------------------------------------------
# Lua emission

def lua_class(chars: set[str]) -> str:
    return "[" + "".join(sorted(chars)) + "]"


def emit(readings, singles, combos) -> str:
    out = io.StringIO()
    w = out.write
    w("-- AUTO-GENERATED by scripts/gen_jp_data.py -- DO NOT EDIT BY HAND\n")
    w(f"-- Source: Unicode Unihan {UNIHAN_VERSION} (kJapanese / kJapaneseOn / kJapaneseKun)\n")
    w("-- License: https://www.unicode.org/license.txt\n")
    w("return {\n")

    w("\treadings = {\n")
    for char in sorted(readings):
        w(f"\t\t[{char!r}] = {{{', '.join(repr(r) for r in readings[char])}}},\n")
    w("\t},\n")

    for n in (1, 2):
        w(f"\tp{n} = {{\n")
        for key in sorted(singles[n]):
            w(f"\t\t[{key!r}] = {lua_class(singles[n][key])!r},\n")
        w("\t},\n")

    # p3: single-char classes merged with two-char youon atoms
    w("\tp3 = {\n")
    for key in sorted(set(singles[3]) | set(combos)):
        parts: list[str] = []
        if singles[3].get(key):
            parts.append(lua_class(singles[3][key]))
        parts.extend(sorted(combos.get(key, set())))
        if len(parts) == 1:
            frag = parts[0]
        else:
            frag = "\\(" + "\\|".join(parts) + "\\)"
        w(f"\t\t[{key!r}] = {frag!r},\n")
    w("\t},\n")

    w("}\n")
    return out.getvalue()


def main():
    readings, singles, combos, n_kana, n_fallback, n_kanji = build()
    OUT.write_text(emit(readings, singles, combos), encoding="utf-8")
    print(f"kanji: {n_kanji} (romaji-fallback: {n_fallback}), kana: {n_kana}")
    print(f"readings: {len(readings)}, p1: {len(singles[1])}, p2: {len(singles[2])}, "
          f"p3: {len(singles[3])}, combo keys: {len(combos)}")
    print(f"wrote {OUT} ({OUT.stat().st_size / 1024:.0f} KB)")


if __name__ == "__main__":
    main()
