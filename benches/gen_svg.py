#!/usr/bin/env python3
"""Generate assets/benchmark.svg from benches/results.json.

Usage (from the repo root, after `nvim -l benches/compare.lua`):

    uv run benches/gen_svg.py

The chart shows the full language-combination matrix: horizontal bars
grouped by mix size (singles / pairs / triples / all four), sorted by
vim-regex mean within each group, with the vim-regex and Rust bars side
by side per category and a summary panel for the overall figures.

Downloads the Inter font (Google Fonts, SIL OFL 1.1) and embeds it as a
base64 @font-face data URI so the SVG renders identically inside GitHub
README <img> tags with no external references. If the download fails the
script exits with an explicit error instead of shipping unembedded fonts.

Python stdlib only.
"""

from __future__ import annotations

import base64
import json
import os
import re
import sys
import urllib.request
from html import escape

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RESULTS = os.path.join(ROOT, "benches", "results.json")
OUT = os.path.join(ROOT, "assets", "benchmark.svg")

# GitHub-ish palette
INK = "#1F2328"
MUTED = "#59636E"
FAINT = "#8c959f"
BORDER = "#d1d9e0"
TRACK = "#eff2f5"
VIM_COLOR = "#bf8700"  # muted amber — the pure-Lua vim-regex path
RUST_COLOR = "#1a7f37"  # green — the native Rust matcher over the persistent server
SPAWN_COLOR = "#8c959f"  # gray — the per-keystroke spawn transport (before)
PANEL_BG = "#f6f8fa"

LANG_NAMES = {
    "zhcn": "Chinese",
    "ja": "Japanese",
    "ko": "Korean",
    "en": "English",
}

GROUP_TITLES = {
    1: "Singles — one language enabled",
    2: "Pairs — two languages enabled",
    3: "Triples — three languages enabled",
    4: "All four languages enabled",
}

FONT_CSS_URL = (
    "https://fonts.googleapis.com/css2?family=Inter:wght@400;700&display=swap"
)
FONT_UA = (
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/124.0 Safari/537.36"
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
    try:
        css = fetch(FONT_CSS_URL).decode("utf-8")
    except Exception as exc:  # noqa: BLE001 - report any network failure
        fail(
            "could not download Inter CSS from Google Fonts "
            f"({exc!r}); refusing to emit an SVG without embedded fonts"
        )
        raise

    # Google's CSS lists several unicode subsets per weight; keep the
    # plain-latin block for each requested weight.
    blocks = re.findall(r"/\*\s*([a-z-]+)\s*\*/\s*@font-face\s*\{(.*?)\}", css, re.S)
    faces: dict[int, str] = {}
    for subset, body in blocks:
        if subset != "latin":
            continue
        weight = re.search(r"font-weight:\s*(\d+)", body)
        url = re.search(r"url\((https://[^)]+\.woff2)\)", body)
        if not (weight and url):
            continue
        w = int(weight.group(1))
        if w in (400, 700) and w not in faces:
            faces[w] = url.group(1)

    missing = [w for w in (400, 700) if w not in faces]
    if missing:
        fail(f"Google Fonts CSS contained no latin woff2 for weights {missing}")

    rules = []
    for weight in (400, 700):
        try:
            data = fetch(faces[weight])
        except Exception as exc:  # noqa: BLE001
            fail(
                f"could not download Inter woff2 (weight {weight}) from "
                f"{faces[weight]} ({exc!r}); refusing to emit an SVG "
                "without embedded fonts"
            )
            raise
        b64 = base64.b64encode(data).decode("ascii")
        rules.append(
            "@font-face{font-family:'InterBench';font-weight:"
            f"{weight};src:url(data:font/woff2;base64,{b64}) "
            "format('woff2');}"
        )
    return "".join(rules)


def fmt_ms(x: float) -> str:
    return f"{x:.1f}" if x >= 10 else f"{x:.2f}"


def fmt_x(x: float) -> str:
    if x >= 10:
        return f"{x:.0f}\u00d7"
    if x < 1:
        return f"{x:.2f}\u00d7"
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
    LEFT, RIGHT = 40, W - 40
    BODY = RIGHT - LEFT
    PANEL_W = 302
    PANEL_X = RIGHT - PANEL_W

    parts = []

    # ---------------------------------------------------------------- header
    # (kept short of PANEL_X so it never runs under the summary panel)
    parts.append(text(LEFT, 48, "flash-cjk.nvim — matcher performance",
                      20, INK, 700))
    parts.append(
        text(LEFT, 70,
             "Per-keystroke search cost: vim-regex path vs native Rust "
             "matcher", 12, MUTED)
    )
    parts.append(
        text(LEFT, 87,
             f"{total_cases} generated windows · 15 language combinations · "
             "sampled from the plugin's data tables", 10.5, MUTED)
    )

    # --------------------------------------------------------- summary panel
    panel_rows = [
        ("mean", overall["vim_ms"]["mean"], overall["rust_server_ms"]["mean"],
         overall["mean_ratio"]),
        ("p50", overall["vim_ms"]["p50"], overall["rust_server_ms"]["p50"], None),
        ("p95", overall["vim_ms"]["p95"], overall["rust_server_ms"]["p95"],
         overall["p95_ratio"]),
    ]
    py = 26
    panel_h = 24 + len(panel_rows) * 17 + 4 + 2 * 15 + 12
    parts.append(rounded(PANEL_X, py, PANEL_W, panel_h, 10, PANEL_BG,
                         stroke=BORDER))
    ty = py + 24
    parts.append(text(PANEL_X + 16, ty,
                      f"Overall — {total_cases} cases", 12, INK, 700))
    ty += 20
    for name, vvim, vrust, ratio in panel_rows:
        parts.append(text(PANEL_X + 16, ty, name, 10.5, MUTED))
        parts.append(
            text(PANEL_X + 52, ty,
                 f"{fmt_ms(vvim)} \u2192 {fmt_ms(vrust)} ms", 10.5, INK, 700)
        )
        if ratio is not None:
            parts.append(
                text(PANEL_X + PANEL_W - 16, ty, fmt_x(ratio), 10.5,
                     RUST_COLOR, 700, "end")
            )
        ty += 17
    ty += 4
    parts.append(
        text(PANEL_X + 16, ty,
             f"Rust floor: {fmt_ms(meta.get('process_spawn_ms', 0))} ms "
             f"spawn + {fmt_ms(meta.get('binary_startup_ms', 0))} ms "
             "startup", 9.5, MUTED)
    )
    parts.append(
        text(PANEL_X + 16, ty + 15,
             f"E872 regex-compile failures: {failures} of {total_cases} "
             "(vim-regex only)", 9.5, MUTED)
    )

    # ---------------------------------------------------------------- legend
    ly = py + panel_h + 22
    parts.append(rounded(LEFT, ly - 9, 12, 12, 3, VIM_COLOR))
    parts.append(text(LEFT + 18, ly, "vim-regex (pure Lua path)", 10.5, MUTED))
    parts.append(rounded(LEFT + 172, ly - 9, 12, 12, 3, RUST_COLOR))
    parts.append(text(LEFT + 190, ly, "Rust over the persistent server (UDS)",
                      10.5, MUTED))
    parts.append(
        text(RIGHT, ly,
             "bars scaled per category · sorted by vim-regex mean · "
             "\u00d7 = ratio of means", 9.5, FAINT, 400, "end")
    )

    # ---------------------------------------------------------------- groups
    # vertical rhythm: a category is 63px (label 16 + two 20px bar slots
    # + 7 clearance); a group header adds 33px. All baselines keep at
    # least a descender's clearance from the element above them.
    y = ly + 26
    for size, cats in groups:
        y += 8
        title = GROUP_TITLES.get(size, f"{size} languages")
        parts.append(text(LEFT, y, title, 13, INK, 700))
        parts.append(
            text(RIGHT, y,
                 f"{len(cats)} categor{'ies' if len(cats) > 1 else 'y'} · "
                 f"{sum(c['cases'] for _, c in cats)} cases", 10, FAINT,
                 400, "end")
        )
        y += 9
        parts.append(hline(LEFT, RIGHT, y, BORDER))
        y += 16

        for _, cat in cats:
            vim_ms = cat["vim_ms"]["mean"]
            rust_ms = cat["rust_server_ms"]["mean"]
            parts.append(text(LEFT, y, cat_label(cat), 12.5, INK, 700))
            parts.append(
                text(RIGHT, y, fmt_x(cat["mean_ratio"]), 11, MUTED, 700,
                     "end")
            )
            y += 16
            ceiling = max(vim_ms, rust_ms) * 1.06
            for ms, color, name in (
                (vim_ms, VIM_COLOR, "vim-regex"),
                (rust_ms, RUST_COLOR, "Rust (server)"),
            ):
                parts.append(rounded(LEFT, y, BODY, 14, 7, TRACK))
                bw = max(6.0, BODY * ms / ceiling)
                parts.append(rounded(LEFT, y, bw, 14, 7, color))
                label_s = f"{name}  {fmt_ms(ms)} ms"
                if bw > 150:
                    parts.append(text(LEFT + 14, y + 11, label_s, 10.5,
                                      "#ffffff", 700))
                else:
                    parts.append(text(LEFT + bw + 10, y + 11, label_s,
                                      10.5, INK, 700))
                y += 20
            y += 7

    # ------------------------------------------------- spawn -> server panel
    # the headline change of the server transport: the per-keystroke
    # process floor is gone. Three metric groups, spawn vs server bars
    # on one shared scale per group.
    y += 18
    parts.append(hline(LEFT, RIGHT, y, BORDER))
    y += 26
    parts.append(text(LEFT, y, "Process overhead eliminated: spawn vs server",
                      15, INK, 700))
    parts.append(
        text(RIGHT, y, "same 1,050 cases · per-keystroke cost of the Rust path",
             10, FAINT, 400, "end")
    )
    y += 14
    groups_panel = [
        ("mean", overall["rust_spawn_ms"]["mean"], overall["rust_server_ms"]["mean"]),
        ("p50", overall["rust_spawn_ms"]["p50"], overall["rust_server_ms"]["p50"]),
        ("p95", overall["rust_spawn_ms"]["p95"], overall["rust_server_ms"]["p95"]),
    ]
    col_w = BODY / 3
    for i, (name, spawn_ms, server_ms) in enumerate(groups_panel):
        cx = LEFT + i * col_w + col_w / 2
        parts.append(text(LEFT + i * col_w + col_w / 2, y, name, 12, INK, 700,
                          "middle"))
        ceiling = max(spawn_ms, server_ms) * 1.06
        bar_area = col_w - 90
        bx = LEFT + i * col_w + 45
        bw_sp = max(6.0, bar_area * spawn_ms / ceiling)
        bw_sv = max(6.0, bar_area * server_ms / ceiling)
        parts.append(rounded(bx, y + 12, bar_area, 13, 6, TRACK))
        parts.append(rounded(bx, y + 12, bw_sp, 13, 6, SPAWN_COLOR))
        parts.append(text(bx + bar_area + 8, y + 23,
                          f"spawn {fmt_ms(spawn_ms)} ms", 10, MUTED, 700))
        parts.append(rounded(bx, y + 33, bar_area, 13, 6, TRACK))
        parts.append(rounded(bx, y + 33, bw_sv, 13, 6, RUST_COLOR))
        parts.append(text(bx + bar_area + 8, y + 44,
                          f"server {fmt_ms(server_ms)} ms", 10, RUST_COLOR, 700))
    y += 62
    spawn_drop = (1 - overall["rust_server_ms"]["mean"]
                  / overall["rust_spawn_ms"]["mean"]) * 100
    parts.append(
        text(LEFT, y,
             f"mean {fmt_x(overall['rust_spawn_ms']['mean'] / overall['rust_server_ms']['mean'])} faster · "
             f"{spawn_drop:.0f}% of the spawn cost was process creation + "
             "data-table startup, paid once at server start instead",
             10, MUTED)
    )
    y += 16

    # ---------------------------------------------------------------- footnote
    fy = y + 10
    parts.append(hline(LEFT, RIGHT, fy, BORDER))
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
        "The spawn panel keeps the per-keystroke process transport "
        "(vim.system + JSON), the fallback path.",
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
    H = int(fy + 18 + len(foot) * 15 + 12)
    for i, line in enumerate(foot):
        parts.append(text(LEFT, fy + 22 + i * 15, line, 9.8, MUTED))

    svg_parts = [
        f"<svg xmlns='http://www.w3.org/2000/svg' width='{W}' height='{H}' "
        f"viewBox='0 0 {W} {H}' role='img' "
        "aria-label='Benchmark: vim-regex path versus native Rust matcher "
        "across the full 15-combination language matrix, per-keystroke "
        "cost'>",
        f"<defs><style>{font_css}text{{font-family:'InterBench',Inter,"
        "'Helvetica Neue',Arial,sans-serif;}}</style></defs>",
    ]
    svg_parts.extend(parts)
    svg_parts.append("</svg>")
    svg = "\n".join(svg_parts)

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
