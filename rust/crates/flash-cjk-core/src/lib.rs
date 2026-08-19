#![forbid(unsafe_code)]

//! flash-cjk-core: multilingual (CN/JP/KO) jump matching core.
//!
//! Mirrors the segmentation semantics of lua/flash-cjk so that a typed
//! pattern produces the same matches as the vim-regex implementation,
//! at a fraction of the cost (see benches/matching.rs).

pub mod charset;
pub mod data;
pub mod matcher;
pub mod parser;
pub mod predict;

pub use charset::CharSet;
pub use matcher::{find_matches, find_matches_vim_semantics, Match};
pub use parser::{compile, Alt, Langs};

/// Convenience: compile + match in one call.
pub fn matches(pattern: &str, lines: &[&str], langs: Langs) -> Vec<Match> {
    let alts = compile(pattern, langs);
    find_matches_vim_semantics(lines, &alts)
}
