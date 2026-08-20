//! Next-letter prediction for the labeler, mirroring the Lua side
//! (`labeler.match_strs` + `lang.zhcn.strs` + `lang.ja.strs` +
//! `lang.ko.strs`): enumerate the spellings the matched text (plus the
//! character right after it) could have been typed as, keep those that
//! start with the current clean pattern, and collect the letter that
//! follows it. Every prediction carries the language whose engine
//! produced it (the labeler's language priority ranks matches by these
//! tags); literal ASCII spans are tagged "en".
use crate::data::{CN_REVERSE, data};
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
    /// Protocol language code for this engine's spellings.
    fn lang(self) -> &'static str {
        match self {
            Engine::Cn => "zhcn",
            Engine::Jp => "ja",
            Engine::Ko => "ko",
        }
    }
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
/// capped like the Lua engines (`lang.ja.strs`/`lang.ko.strs` cap at 64;
/// `lang.zhcn.strs` is uncapped but match texts are a few chars long).
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
    if langs.zhcn {
        out.extend(engine_spellings(text, Engine::Cn, false));
    }
    if langs.ja {
        out.extend(engine_spellings(text, Engine::Jp, true));
    }
    if langs.ko {
        out.extend(engine_spellings(text, Engine::Ko, true));
    }
    out
}

/// Per-match prediction: the letters the user may type next (spellings
/// starting with `clean_pattern` contribute the letter at byte position
/// `clean_pattern.len()`) and the languages the current pattern could
/// have reached `text` through -- one tag per engine with at least one
/// such spelling, plus "en" for literal ASCII spans. Mirrors
/// `labeler.match_langs` on the Lua side.
pub fn predict(
    clean_pattern: &str,
    text: &str,
    langs: &crate::parser::Langs,
) -> (Vec<char>, Vec<&'static str>) {
    let plen = clean_pattern.len();
    let mut letters: Vec<char> = Vec::new();
    let mut tags: Vec<&'static str> = Vec::new();
    // Text starting with a literal ASCII alphanumeric is reached in
    // the "en" domain: engines pass ASCII through unchanged, so their
    // spellings carry no language information for such spans -- they
    // still contribute letters, but never a tag.
    let literal = text
        .chars()
        .next()
        .is_some_and(|c| c.is_ascii_alphanumeric());
    let engines = [
        (Engine::Cn, langs.zhcn, false),
        (Engine::Jp, langs.ja, true),
        (Engine::Ko, langs.ko, true),
    ];
    for &(engine, on, capped) in engines.iter() {
        if !on {
            continue;
        }
        let mut tagged = false;
        for s in engine_spellings(text, engine, capped) {
            if s.as_bytes().starts_with(clean_pattern.as_bytes()) {
                tagged = !literal;
                if s.len() > plen {
                    let c = s[plen..].chars().next().unwrap();
                    if !letters.contains(&c) {
                        letters.push(c);
                    }
                }
            }
        }
        if tagged {
            tags.push(engine.lang());
        }
    }
    if literal && langs.en {
        tags.push("en");
    }
    (letters, tags)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::parser::Langs;

    #[test]
    fn predicts_continuation_of_kanji_reading() {
        // 日 spells include "nichi": with pattern "n" the next letter is i
        let langs = Langs::default();
        let (letters, _) = predict("n", "日", &langs);
        assert!(letters.contains(&'i'), "{letters:?}");
    }

    #[test]
    fn predicts_next_char_first_letter_when_covered() {
        // pattern "ni" fully covers 日 (spelled niki/niti/nichi/...);
        // continuations pick up 本: k/t/c
        let langs = Langs::default();
        let (letters, _) = predict("ni", "日本", &langs);
        assert!(letters.contains(&'t'), "{letters:?}"); // niti...
        assert!(letters.contains(&'k'), "{letters:?}"); // niki...
        assert!(letters.contains(&'c'), "{letters:?}"); // nichi...
    }

    #[test]
    fn korean_two_set_prediction() {
        let langs = Langs::default();
        // 안 spells: an (romaja), dks (two-set); pattern "d" -> next k
        let (letters, tags) = predict("d", "안", &langs);
        assert!(letters.contains(&'k'), "{letters:?}");
        assert_eq!(tags, vec!["ko"]);
    }

    #[test]
    fn ascii_passthrough() {
        let langs = Langs::default();
        let (letters, tags) = predict("n", "nice", &langs);
        assert!(letters.contains(&'i'));
        // literal ASCII span: attributed to "en" only, never to the
        // CJK engines whose spellings happen to pass ASCII through
        assert_eq!(tags, vec!["en"]);
    }

    #[test]
    fn tags_every_engine_that_extends_the_pattern() {
        // 梯 is xiaohe "ti" and reads tai/tei in Japanese: pattern "t"
        // is reachable through both engines
        let langs = Langs::default();
        let (_, tags) = predict("t", "梯", &langs);
        assert!(tags.contains(&"zhcn") && tags.contains(&"ja"), "{tags:?}");
        // ち is kana: only the Japanese engine can extend "ti"
        let (_, tags) = predict("ti", "ち", &langs);
        assert_eq!(tags, vec!["ja"]);
    }

    #[test]
    fn tags_follow_the_enabled_languages() {
        let langs = Langs {
            zhcn: false,
            ja: true,
            ko: false,
            en: false,
            alpha_mixing: true,
        };
        let (_, tags) = predict("t", "梯", &langs);
        assert_eq!(tags, vec!["ja"]);
        let (_, tags) = predict("n", "nice", &langs);
        assert!(tags.is_empty());
    }
}
