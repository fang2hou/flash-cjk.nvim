#![forbid(unsafe_code)]

//! flash-cjk-search: stdin/stdout JSON matcher for flash-cjk.nvim.
//!
//! Protocol: one JSON request on stdin, one JSON response on stdout.
//! Request:  {"pattern": "ti", "lines": ["..", ".."], "langs": {...}}
//! Response: {"matches": [[line, byte_col, byte_len], ...],
//!           "predictions": ["i", ...],
//!           "pred_langs": [["ja"], ...]}

use std::io::{self, Read, Write};

use anyhow::Context;
use flash_cjk_core::{Langs, matches};
use serde::{Deserialize, Serialize};

#[derive(Deserialize)]
struct Request {
    pattern: String,
    lines: Vec<String>,
    #[serde(default)]
    langs: LangsSpec,
}

/// Language flags; absent fields default to enabled (mirrors the Lua
/// config defaults).
#[derive(Deserialize, Default)]
#[serde(default)]
struct LangsSpec {
    #[serde(default = "default_true")]
    zhcn: bool,
    #[serde(default = "default_true")]
    ja: bool,
    #[serde(default = "default_true")]
    ko: bool,
    #[serde(default = "default_true")]
    en: bool,
    #[serde(default = "default_true")]
    alpha_mixing: bool,
}

fn default_true() -> bool {
    true
}

impl From<LangsSpec> for Langs {
    fn from(s: LangsSpec) -> Self {
        Langs {
            zhcn: s.zhcn,
            ja: s.ja,
            ko: s.ko,
            en: s.en,
            alpha_mixing: s.alpha_mixing,
        }
    }
}

#[derive(Serialize)]
struct Response {
    /// (line index, byte column, last-char byte column, byte length)
    matches: Vec<[usize; 4]>,
    /// per-match predicted next letters (may be empty)
    predictions: Vec<String>,
    /// per-match attributed language codes, parallel to `matches`:
    /// the languages the current pattern could have reached the match
    /// through ("zhcn"/"ja"/"ko" for engine spellings, "en" for
    /// literal ASCII spans; may be empty, e.g. punctuation)
    pred_langs: Vec<Vec<String>>,
}

fn run() -> anyhow::Result<()> {
    let mut input = String::new();
    io::stdin()
        .read_to_string(&mut input)
        .context("reading request from stdin")?;
    let req: Request = serde_json::from_str(&input).context("parsing request JSON")?;
    let line_refs: Vec<&str> = req.lines.iter().map(String::as_str).collect();
    let langs = Langs::from(req.langs);
    let found = matches(&req.pattern, &line_refs, langs);
    // labeler prediction per match: the matched text plus the character
    // right after it (mirrors labeler.match_strs on the Lua side)
    let (clean, _) = flash_cjk_core::parser::parse_forced(&req.pattern);
    let mut predictions: Vec<String> = Vec::with_capacity(found.len());
    let mut pred_langs: Vec<Vec<String>> = Vec::with_capacity(found.len());
    for m in &found {
        let line = &req.lines[m.line];
        let start = m.col;
        let end = m.col + m.len;
        let next_end = line[end..]
            .chars()
            .next()
            .map(|c| end + c.len_utf8())
            .unwrap_or(end);
        let text = &line[start..next_end];
        let (letters, tags) = flash_cjk_core::predict::predict(&clean, text, &langs);
        predictions.push(letters.into_iter().collect());
        pred_langs.push(tags.into_iter().map(str::to_string).collect());
    }
    let resp = Response {
        matches: found
            .into_iter()
            .map(|m| [m.line, m.col, m.end_col, m.len])
            .collect(),
        predictions,
        pred_langs,
    };
    let mut out = io::stdout().lock();
    serde_json::to_writer(&mut out, &resp).context("writing response")?;
    out.write_all(b"\n").ok();
    Ok(())
}

fn main() -> anyhow::Result<()> {
    run()
}
