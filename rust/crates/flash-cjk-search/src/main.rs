#![forbid(unsafe_code)]

//! flash-cjk-search: JSON matcher for flash-cjk.nvim.
//!
//! Two modes:
//!  * one-shot (default): one JSON request on stdin, one JSON response
//!    on stdout — the per-keystroke spawn path.
//!  * `serve --socket <path>`: a persistent Unix domain socket server
//!    speaking one NDJSON request per line per connection, so the
//!    per-keystroke process spawn and data-table startup are paid once.
//!    Unix only; see src/serve.rs for the lifecycle contract.
//!
//! Protocol: one JSON request on stdin, one JSON response on stdout.
//! Request:  {"pattern": "ti", "lines": ["..", ".."], "langs": {...}}
//!           (serve envelope adds "pid" and an optional "cmd")
//! Response: {"matches": [[line, byte_col, byte_len], ...],
//!           "predictions": ["i", ...],
//!           "pred_langs": [["ja"], ...]}

use std::io::{self, Read, Write};

use anyhow::Context;
use flash_cjk_core::{Langs, matches};
use serde::{Deserialize, Serialize};

#[cfg(unix)]
mod serve;

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
    mixed_input: bool,
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
            mixed_input: s.mixed_input,
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
/// Computes the response for one search request — shared by the
/// one-shot stdin mode and the serve mode, so both transports are
/// byte-identical by construction.
fn answer(pattern: &str, lines: &[String], langs: Langs) -> Response {
    let line_refs: Vec<&str> = lines.iter().map(String::as_str).collect();
    let found = matches(pattern, &line_refs, langs);
    // labeler prediction per match: the matched text plus the character
    // right after it (mirrors labeler.match_strs on the Lua side)
    let (clean, _) = flash_cjk_core::parser::parse_forced(pattern);
    let mut predictions: Vec<String> = Vec::with_capacity(found.len());
    let mut pred_langs: Vec<Vec<String>> = Vec::with_capacity(found.len());
    for m in &found {
        let line = &lines[m.line];
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
    Response {
        matches: found
            .into_iter()
            .map(|m| [m.line, m.col, m.end_col, m.len])
            .collect(),
        predictions,
        pred_langs,
    }
}

/// One-shot stdin mode: read one JSON request, write one JSON response.
fn run() -> anyhow::Result<()> {
    let mut input = String::new();
    io::stdin()
        .read_to_string(&mut input)
        .context("reading request from stdin")?;
    let req: Request = serde_json::from_str(&input).context("parsing request JSON")?;
    let resp = answer(&req.pattern, &req.lines, Langs::from(req.langs));
    let mut out = io::stdout().lock();
    serde_json::to_writer(&mut out, &resp).context("writing response")?;
    out.write_all(b"\n").ok();
    Ok(())
}

fn main() -> anyhow::Result<()> {
    let args: Vec<String> = std::env::args().collect();
    #[cfg(unix)]
    if args.get(1).map(String::as_str) == Some("serve") {
        return serve::main(&args[2..]);
    }
    run()
}
