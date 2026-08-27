#!/usr/bin/env python3
"""Generate assets/benchmark.svg from benches/results.json.

Usage (from the repo root, after `nvim -l benches/compare.lua`):

    uv run benches/gen_svg.py

Editorial warm-paper design: letterspaced overline, a big-number stats
band, one card per mix-size group with pill bars (terracotta = the
vim-regex path, deep teal = the Rust matcher), and a hairline footer
with the methodology.

Downloads the Inter font (Google Fonts, SIL OFL 1.1) and embeds it as a
base64 @font-face data URI so the SVG renders identically inside GitHub
README <img> tags with no external references. If the download fails the
script exits with an explicit error instead of shipping unembedded fonts.

Python stdlib only.
"""

from __future__ import annotations

import base64
import json
import math
import os
import re
import sys
import urllib.request
from html import escape

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RESULTS = os.path.join(ROOT, "benches", "results.json")
OUT = os.path.join(ROOT, "assets", "benchmark.svg")

# Warm-paper palette
PAGE = "#FAF6EE"  # warm white page
CARD = "#FFFDF7"  # group card, a step lighter than the page
INK = "#2B2620"  # warm near-black
MUTED = "#6E6355"  # warm gray
FAINT = "#988C7B"
HAIRLINE = "#E6DCC8"  # rules and card borders
GRIDLINE = "#EFE6D4"  # log-scale gridlines
TRACK = "#F0E8D8"  # bar track
VIM_COLOR = "#BC5434"  # terracotta — the pure-Lua vim-regex path
RUST_COLOR = "#1E6B60"  # deep teal — the native Rust matcher (UDS server)

LANG_NAMES = {
    "zhcn": "zhcn",
    "ja": "ja",
    "ko": "ko",
    "en": "en",
}

GROUP_TITLES = {
    1: "Single language",
    2: "Two languages",
    3: "Three languages",
    4: "All four languages",
}

FONT_CSS_URL = (
    "https://fonts.googleapis.com/css2?family=Inter:wght@400;700&display=swap"
)
FONT_UA = (
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/120.0 Safari/537.36"
)


def fail(msg: str) -> None:
    print(f"ERROR: {msg}", file=sys.stderr)
    sys.exit(1)


def fetch(url: str) -> bytes:
    req = urllib.request.Request(url, headers={"User-Agent": FONT_UA})
    with urllib.request.urlopen(req, timeout=30) as resp:
        return resp.read()


def embed_fonts() -> str:
    """Download Inter (400 + 700, latin subset) and return @font-face CSS."""
    css = fetch(FONT_CSS_URL).decode("utf-8")
    rules = []
    seen = set()
    for block in css.split("@font-face")[1:]:
        weight_m = re.search(r"font-weight:\s*(\d+)", block)
        url_m = re.search(r"src:\s*url\(([^)]+\.woff2)\)", block)
        range_m = re.search(r"unicode-range:\s*([^;]+);", block)
        if not (weight_m and url_m and range_m):
            continue
        weight, url, urange = weight_m.group(1), url_m.group(1), range_m.group(1)
        # latin subset only: the extra cyrillic/greek/vietnamese faces
        # quadruple the embedded bytes for zero visible benefit
        if "U+0000-00FF" not in urange:
            continue
        key = (weight, urange)
        seen.add(key)
        data = fetch(url)
        b64 = base64.b64encode(data).decode("ascii")
        rules.append(
            "@font-face{font-family:'InterBench';font-style:normal;"
            f"font-weight:{weight};font-display:block;"
            f"src:url(data:font/woff2;base64,{b64}) format('woff2');"
            f"unicode-range:{urange};}}"
        )
    if not rules:
        fail("no Inter woff2 faces parsed from the Google Fonts CSS")
    return "".join(rules)


def fmt_ms(x: float) -> str:
    return f"{x:.1f}" if x >= 10 else f"{x:.2f}"


def fmt_x(x: float) -> str:
    if x >= 10:
        return f"{x:.0f}\u00d7"
    if x >= 2:
        return f"{x:.1f}\u00d7"
    return f"{x:.1f}\u00d7"


def text(x: float, y: float, s: str, size: float, fill: str, weight: int = 400,
         anchor: str = "start", spacing: float = 0.0) -> str:
    extra = f" letter-spacing='{spacing}'" if spacing else ""
    return (
        f"<text x='{x:.1f}' y='{y:.1f}' font-size='{size}' fill='{fill}' "
        f"font-weight='{weight}' text-anchor='{anchor}'{extra}>"
        f"{escape(s)}</text>"
    )


def rounded(x: float, y: float, w: float, h: float, r: float, fill: str,
            stroke: str | None = None) -> str:
    st = f" stroke='{stroke}'" if stroke else ""
    return (
        f"<rect x='{x:.1f}' y='{y:.1f}' width='{w:.1f}' height='{h:.1f}' "
        f"rx='{r}' fill='{fill}'{st}/>"
    )


def hline(x1: float, x2: float, y: float, color: str) -> str:
    return (
        f"<line x1='{x1:.1f}' y1='{y:.1f}' x2='{x2:.1f}' y2='{y:.1f}' "
        f"stroke='{color}' stroke-width='1'/>"
    )


def cat_label(cat: dict) -> str:
    return " + ".join(LANG_NAMES[c] for c in cat["languages"])


def main() -> None:
    if not os.path.isfile(RESULTS):
        fail(f"{RESULTS} not found - run `nvim -l benches/compare.lua` first")
    with open(RESULTS, encoding="utf-8") as fh:
        results = json.load(fh)

    overall = results["overall"]
    meta = results["meta"]
    total_cases = overall["cases"]
    failures = overall.get("vim_regex_failures", 0)

    # group the categories by mix size; within a group sort by the
    # vim-regex mean (heaviest first), with the id as a deterministic
    # tie-break
    by_size: dict[int, list[tuple[str, dict]]] = {}
    for key, cat in results["categories"].items():
        by_size.setdefault(len(cat["languages"]), []).append((key, cat))
    groups = sorted(by_size.items())
    for _, cats in groups:
        cats.sort(key=lambda kc: (-kc[1]["vim_ms"]["mean"], kc[0]))

    font_css = embed_fonts()

    W = 960
    MARGIN = 44
    LEFT, RIGHT = MARGIN, W - MARGIN
    BODY = RIGHT - LEFT

    parts = []

    # ------------------------------------------------------------------ page
    parts.append(f"<rect width='{W}' height='__H__' fill='{PAGE}'/>")
    # double rule under the masthead, editorial style
    parts.append(hline(LEFT, RIGHT, 66.5, INK))
    parts.append(hline(LEFT, RIGHT, 70.5, HAIRLINE))

    # -------------------------------------------------------------- masthead
    parts.append(text(LEFT, 34, "FLASH-CJK.NVIM", 11, MUTED, 700,
                      spacing=3.2))
    parts.append(text(RIGHT, 34, "MATCHER PERFORMANCE", 11, FAINT, 400,
                      "end", spacing=3.2))
    parts.append(text(LEFT, 56, "vim-regex path vs the native Rust matcher",
                      22, INK, 700))
    parts.append(
        text(LEFT, 86,
             f"Per-keystroke search cost across {total_cases} generated "
             "windows · 15 language combinations · "
             "sampled from the plugin's data tables", 11.5, MUTED)
    )

    # ------------------------------------------------------------- stats band
    # three big numbers over hairline separators, magazine-summary style
    sy = 104
    stats = [
        (fmt_x(overall["mean_ratio"]), "mean speedup", RUST_COLOR),
        (f"{fmt_ms(overall['vim_ms']['mean'])} \u2192 "
         f"{fmt_ms(overall['rust_server_ms']['mean'])} ms", "mean, vim \u2192 rust",
         INK),
        (f"{fmt_ms(overall['vim_ms']['p95'])} \u2192 "
         f"{fmt_ms(overall['rust_server_ms']['p95'])} ms", "p95, vim \u2192 rust",
         INK),
    ]
    col_w = BODY / 3
    for i, (big, small, color) in enumerate(stats):
        cx = LEFT + i * col_w
        if i:
            parts.append(hline(cx - 12, cx - 12, sy + 4, HAIRLINE))
        parts.append(text(cx, sy + 26, big, 24, color, 700))
        parts.append(text(cx, sy + 44, small, 10.5, MUTED, 400,
                          spacing=1.2))

    # ----------------------------------------------------------------- legend
    ly = sy + 68
    parts.append(rounded(LEFT, ly - 9, 11, 11, 3.5, VIM_COLOR))
    parts.append(text(LEFT + 17, ly, "vim-regex (pure Lua path)", 10.5, MUTED))
    parts.append(rounded(LEFT + 164, ly - 9, 11, 11, 3.5, RUST_COLOR))
    parts.append(text(LEFT + 181, ly, "Rust over the persistent server (UDS)",
                      10.5, MUTED))
    parts.append(
        text(RIGHT, ly,
             "log scale, shared across categories",
             9.5, FAINT, 400, "end")
    )
    parts.append(
        text(LEFT + 181 + 232, ly,
             "×: teal = Rust faster · terracotta = slower", 9.5, FAINT)
    )

    # ------------------------------------------------------------------ cards
    # vertical rhythm: a category is 63px (label 16 + two 20px bar slots
    # + 7 clearance); a card adds its own padding and gap. Bars share one
    # global log scale so lengths compare across cards.
    CARD_PAD_X = 18
    CARD_PAD_TOP = 16
    all_means = [
        ms
        for _, cats in groups
        for _, c in cats
        for ms in (c["vim_ms"]["mean"], c["rust_server_ms"]["mean"])
    ]
    log_lo = math.log10(min(all_means) * 0.85)
    log_hi = math.log10(max(all_means) * 1.15)
    ticks = [t for t in (0.1, 1.0, 10.0)
             if log_lo <= math.log10(t) <= log_hi]
    # right rail: values align in a gutter past the bar zone so labels
    # never sit on a bar tip
    GUTTER = 118

    def bar_w(ms: float, zone: float) -> float:
        frac = (math.log10(ms) - log_lo) / (log_hi - log_lo)
        return max(5.0, zone * frac)

    y = ly + 20
    for size, cats in groups:
        n_rows = len(cats)
        zone_h = n_rows * 63 - 7
        # header = title row 16 + rule row 16 + tick row 16 + gap 4;
        # header = title row 16 + rule/tick band 16 + gap 4 past
        # CARD_PAD_TOP; card_h accounts for it so rows never cross
        # the border
        HEADER_H = 36
        card_h = CARD_PAD_TOP + HEADER_H + zone_h + 12
        parts.append(rounded(LEFT, y, BODY, card_h, 14, CARD,
                             stroke=HAIRLINE))
        iy = y + CARD_PAD_TOP
        title = GROUP_TITLES.get(size, f"{size} languages")
        parts.append(text(LEFT + CARD_PAD_X, iy + 10, title.upper(), 11,
                          MUTED, 700, spacing=2.2))
        parts.append(
            text(RIGHT - CARD_PAD_X, iy + 10,
                 f"{sum(c['cases'] for _, c in cats)} cases · "
                 f"{n_rows} categor{'ies' if n_rows > 1 else 'y'}", 10,
                 FAINT, 400, "end")
        )
        # header row breathes: rule sits clearly below the title
        # baseline, tick labels between rule and first category row
        bx = LEFT + CARD_PAD_X
        zone = BODY - 2 * CARD_PAD_X - GUTTER
        iy += 16
        parts.append(hline(bx, bx + zone, iy, HAIRLINE))
        iy += 16
        # log-scale gridlines behind the bars, labelled in every card
        for t in ticks:
            gx = bx + zone * (math.log10(t) - log_lo) / (log_hi - log_lo)
            parts.append(
                f"<line x1='{gx:.1f}' y1='{iy - 2:.1f}' x2='{gx:.1f}' "
                f"y2='{iy + zone_h - 6:.1f}' stroke='{GRIDLINE}'/>"
            )
            parts.append(text(gx + 4, iy - 8, f"{fmt_ms(t)} ms", 8.5,
                              MUTED))
        iy += 4  # breathing room between the tick row and first category
        for _, cat in cats:
            vim_ms = cat["vim_ms"]["mean"]
            rust_ms = cat["rust_server_ms"]["mean"]
            ratio = cat["mean_ratio"]
            ratio_color = (RUST_COLOR if ratio >= 1.5
                           else VIM_COLOR if ratio < 1 else MUTED)
            parts.append(text(bx, iy, cat_label(cat), 12.5, INK, 700))
            parts.append(
                text(RIGHT - CARD_PAD_X, iy, fmt_x(ratio), 12, ratio_color,
                     700, "end")
            )
            iy += 16
            for ms, color, name in (
                (vim_ms, VIM_COLOR, "vim-regex"),
                (rust_ms, RUST_COLOR, "Rust (server)"),
            ):
                parts.append(rounded(bx, iy, zone, 14, 7, TRACK))
                parts.append(rounded(bx, iy, bar_w(ms, zone), 14, 7, color))
                parts.append(
                    text(RIGHT - CARD_PAD_X, iy + 11,
                         f"{name}  {fmt_ms(ms)} ms", 10.5, INK, 700, "end")
                )
                iy += 20
            iy += 7
        y += card_h + 14
    # --------------------------------------------------------------- footnote
    fy = y + 2
    parts.append(hline(LEFT, RIGHT, fy, HAIRLINE))
    matrix = meta.get("matrix") or (
        f"{len(results['categories'])} language combinations"
    )
    foot = [
        f"Methodology: {total_cases:,} cases — {matrix} · "
        "20-60 lines per window,",
        "characters sampled from the plugin's own data tables · patterns "
        "of 1-6 plausible keystrokes · deterministic seed.",
        "Per case: warmup pass, then the median of 3 passes. Rust rides "
        "the persistent server (one UDS request per keystroke).",
        f"Short prefixes favor vim-regex on the lightest singles "
        f"(p50 {fmt_ms(overall['vim_ms']['p50'])} vs "
        f"{fmt_ms(overall['rust_server_ms']['p50'])} ms); richer mixes "
        "grow the vim-regex tail while the server path stays flat.",
    ]
    if failures:
        foot.append(
            f"{failures} of {total_cases} patterns exceeded Vim's NFA "
            "capture-group limit (E872) and have no vim-regex timing; "
            "the Rust matcher handled all of them."
        )
    foot.append(
        f"{meta['cpu']} · {meta['os']} · Neovim {meta['neovim']} · "
        f"UDS floor {fmt_ms(meta.get('uds_roundtrip_ms', 0))} ms · "
        f"server RSS {meta.get('server_rss_kb', 0) / 1024:.1f} MB · "
        f"{meta['date']} · rerun: nvim -l benches/compare.lua"
    )
    # footnote lines must fit the body width; ~0.52 em average advance
    # for Inter regular at this size is a safe upper bound
    for line in foot:
        if len(line) * 9.8 * 0.52 > BODY:
            fail(
                f"footnote line exceeds the {BODY}px body width "
                f"({line[:50]}...)"
            )
    H = int(fy + 18 + len(foot) * 15 + 16)
    for i, line in enumerate(foot):
        parts.append(text(LEFT, fy + 22 + i * 15, line, 9.8, MUTED))

    svg_parts = [
        f"<svg xmlns='http://www.w3.org/2000/svg' width='{W}' height='{H}' "
        f"viewBox='0 0 {W} {H}' role='img' "
        "aria-label='Benchmark: vim-regex path versus the native Rust "
        "matcher over the persistent server across the full "
        "15-combination language matrix, per-keystroke cost'>",
        f"<defs><style>{font_css}text{{font-family:'InterBench',Inter,"
        "'Helvetica Neue',Arial,sans-serif;}}</style></defs>",
    ]
    svg_parts.extend(parts)
    svg_parts.append("</svg>")
    svg = "\n".join(svg_parts).replace("__H__", str(H))

    if len(svg.encode("utf-8")) > 300_000:
        fail(
            f"generated SVG is {len(svg.encode('utf-8'))} bytes "
            "(> 300 KB budget)"
        )

    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w", encoding="utf-8") as fh:
        fh.write(svg)
    print(
        f"wrote {OUT} ({len(svg.encode('utf-8')) / 1024:.0f} KB, "
        f"{W}x{H}, mean ratio {fmt_x(overall['mean_ratio'])}, "
        f"p95 ratio {fmt_x(overall['p95_ratio'])})"
    )


if __name__ == "__main__":
    main()
