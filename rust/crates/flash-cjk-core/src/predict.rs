//! Next-letter prediction for the labeler, mirroring the Lua side
//! (`labeler.match_strs` + `pinyin.pinyin` + `jp.romaji_strs` +
//! `ko.strs`): enumerate the spellings the matched text (plus the
//! character right after it) could have been typed as, keep those that
//! start with the current clean pattern, and collect the letter that
//! follows it.

use crate::data::{data, CN_REVERSE};
/// Korean syllable -> spellings (romaji variants + two-set keys),
/// mirroring ko.lua `strs`.
fn ko_spellings(ch: char) -> Vec<String> {
    let cp = ch as u32;
    if !(0xAC00..=0xD7A3).contains(&cp) {
        return vec![ch.to_string()];
    }
    let idx = (cp - 0xAC00) as usize;
    let (l, v, t) = (idx / 588, (idx % 588) / 28, idx % 28);
    let d = data();
    let mut out: Vec<String> = Vec::new();
    for lr in d.ko_l_roma(l) {
        out.push(format!("{lr}{}{}", d.ko_v_roma(v), d.ko_t_roma(t)));
    }
    if let Some(ks) = d.ko_key_seq(l, v, t) {
        out.push(ks);
    }
    out
}

const MAX_SPELLINGS: usize = 64;

#[derive(Clone, Copy)]
enum Engine {
    Cn,
    Jp,
    Ko,
}

impl Engine {
    /// The spellings one character has under this engine; unknown
    /// characters pass through literally (mirroring the Lua side).
    fn spellings_of(self, ch: char) -> Vec<String> {
        if ch.is_ascii() {
            return vec![ch.to_string()];
        }
        let d = data();
        match self {
            Engine::Cn => CN_REVERSE
                .get(&ch)
                .map(|v| v.to_vec())
                .unwrap_or_else(|| vec![ch.to_string()]),
            Engine::Jp => d
                .jp_readings(ch)
                .map(|v| v.to_vec())
                .unwrap_or_else(|| vec![ch.to_string()]),
            Engine::Ko => ko_spellings(ch),
        }
    }
}

/// Expands `text` under one engine (per-character cartesian product),
/// capped like the Lua engines (`romaji_strs`/`ko.strs` cap at 64;
/// `pinyin.pinyin` is uncapped but match texts are a few chars long).
fn engine_spellings(text: &str, engine: Engine, capped: bool) -> Vec<String> {
    let mut strs: Vec<String> = vec![String::new()];
    for ch in text.chars() {
        let options = engine.spellings_of(ch);
        let mut next: Vec<String> = Vec::new();
        'outer: for s in &strs {
            for o in &options {
                if capped && next.len() >= MAX_SPELLINGS {
                    break 'outer;
                }
                let mut combined = String::with_capacity(s.len() + o.len());
                combined.push_str(s);
                combined.push_str(o);
                next.push(combined);
            }
        }
        strs = next;
    }
    strs
}

/// All spellings of `text` under the enabled languages. Each engine is
/// expanded independently and the lists are concatenated -- exactly what
/// the Lua labeler does (no cross-language combinations).
pub fn spellings(text: &str, langs: &crate::parser::Langs) -> Vec<String> {
    let mut out = Vec::new();
    if langs.cn {
        out.extend(engine_spellings(text, Engine::Cn, false));
    }
    if langs.jp {
        out.extend(engine_spellings(text, Engine::Jp, true));
    }
    if langs.ko {
        out.extend(engine_spellings(text, Engine::Ko, true));
    }
    out
}

/// The set of letters the user may type next: spellings starting with
/// `clean_pattern` (ascii) contribute their next letter at byte position
/// `pattern.len()`.
pub fn next_letters(clean_pattern: &str, text: &str, langs: &crate::parser::Langs) -> Vec<char> {
    let plen = clean_pattern.len();
    let mut out = Vec::new();
    for s in spellings(text, langs) {
        if s.len() > plen && s.as_bytes().starts_with(clean_pattern.as_bytes()) {
            let c = s[plen..].chars().next().unwrap();
            if !out.contains(&c) {
                out.push(c);
            }
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::parser::Langs;

    #[test]
    fn predicts_continuation_of_kanji_reading() {
        // 日 spells include "nichi": with pattern "n" the next letter is i
        let langs = Langs::default();
        let letters = next_letters("n", "日", &langs);
        assert!(letters.contains(&'i'), "{letters:?}");
    }

    #[test]
    fn predicts_next_char_first_letter_when_covered() {
        // pattern "ni" fully covers 日 (spelled niki/niti/nichi/...);
        // continuations pick up 本: k/t/c
        let langs = Langs::default();
        let letters = next_letters("ni", "日本", &langs);
        assert!(letters.contains(&'t'), "{letters:?}"); // niti...
        assert!(letters.contains(&'k'), "{letters:?}"); // niki...
        assert!(letters.contains(&'c'), "{letters:?}"); // nichi...
    }

    #[test]
    fn korean_two_set_prediction() {
        let langs = Langs::default();
        // 안 spells: an (romaja), dks (two-set); pattern "d" -> next k
        let letters = next_letters("d", "안", &langs);
        assert!(letters.contains(&'k'), "{letters:?}");
    }

    #[test]
    fn ascii_passthrough() {
        let langs = Langs::default();
        let letters = next_letters("n", "nice", &langs);
        assert!(letters.contains(&'i'));
    }
}
