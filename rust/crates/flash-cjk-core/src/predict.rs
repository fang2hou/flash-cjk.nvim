//! Next-letter prediction for the labeler, mirroring the Lua side
//! (`labeler.match_strs` + `lang.zhcn.strs` + `lang.ja.strs` +
//! `lang.ko.strs`): enumerate the spellings the matched text (plus the
//! character right after it) could have been typed as, keep those that
//! start with the current clean pattern, and collect the letter that
//! follows it. Every prediction carries the language whose engine
//! produced it (the labeler's language priority ranks matches by these
//! tags); literal ASCII spans are tagged "en".
use crate::data::{CN_REVERSE, data};
use crate::parser::{jp_consonant, jp_vowel};
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

#[derive(Clone, Copy, PartialEq)]
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

    /// The spellings starting at `chars[i]` and how many characters
    /// they consume: Japanese geminates and long-vowel marks cover
    /// more (or depend on more) than the single character, youon
    /// pairs fold into one unit, every other case is one character.
    fn step(self, chars: &[char], i: usize) -> (Vec<String>, usize) {
        if self == Engine::Jp {
            if let Some(merged) = jp_merged_step(chars, i) {
                return merged;
            }
            // youon pairs (きゃ -> kya, しぇ -> she) fold into one
            // unit, like the Lua engine's SMALL_Y/SMALL_E merge
            if let Some((folded, 2)) = jp_unit_readings(chars, i).filter(|(_, span)| *span == 2) {
                return (folded, 2);
            }
        }
        (self.spellings_of(chars[i]), 1)
    }
}

/// Expands `text` under one engine (cartesian product over per-unit
/// spellings), capped like the Lua engines (`lang.ja.strs`/`lang.ko.strs`
/// cap at 64; `lang.zhcn.strs` is uncapped but match texts are a few
/// chars long). A unit is one character except for the Japanese merges
/// in `jp_merged_step` and the youon folds in `Engine::step`.
fn engine_spellings(text: &str, engine: Engine, capped: bool) -> Vec<String> {
    let chars: Vec<char> = text.chars().collect();
    let mut strs: Vec<String> = vec![String::new()];
    let mut i = 0;
    while i < chars.len() {
        let (options, step) = engine.step(&chars, i);
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
        i += step;
    }
    strs
}

/// The vowel a small kana (youon second half) adds, if any: ゃゅょ for
/// the y-glide combos and ぇ for the she/che/je spellings.
fn youon_vowel(c: char) -> Option<char> {
    match c {
        'ゃ' | 'ャ' => Some('a'),
        'ゅ' | 'ュ' => Some('u'),
        'ょ' | 'ョ' => Some('o'),
        'ぇ' | 'ェ' => Some('e'),
        _ => None,
    }
}

/// The effective readings of the Japanese unit starting at `chars[j]`
/// and how many characters it spans: a base kana plus a following
/// small kana (ゃゅょ, and ぇ for the she/che/je spellings) folds into
/// youon spellings (きゃ -> kya, しゃ -> sha, しぇ -> she), exactly
/// like merge_youon + SMALL_E in lang/ja/init.lua. Unknown characters
/// have no unit readings.
fn jp_unit_readings(chars: &[char], j: usize) -> Option<(Vec<String>, usize)> {
    let ch = *chars.get(j)?;
    let readings = data().jp_readings(ch)?;
    let Some(v) = chars.get(j + 1).copied().and_then(youon_vowel) else {
        return Some((readings.clone(), 1));
    };
    let mut folded: Vec<String> = Vec::with_capacity(readings.len());
    for r in readings {
        if r.chars().count() >= 2 && r.ends_with('i') {
            // shi/chi/ji drop their vowel before the y: sha, not shiya
            let stem = &r[..r.len() - 1];
            if matches!(r.as_str(), "shi" | "chi" | "ji") {
                folded.push(format!("{stem}{v}"));
            } else {
                folded.push(format!("{stem}y{v}"));
            }
        } else {
            folded.push(r.clone());
        }
    }
    Some((folded, 2))
}

/// Japanese-only multi-character spellings, mirroring lang/ja/init.lua
/// `strs`:
/// - っ/ッ doubles the onset of the following unit's readings (って ->
///   tte, っちゃ -> tcha/ttya; readings with a vowel or n onset have no
///   doubled form). When the next unit is unknown or none of its
///   readings doubles, っ keeps its own spellings (ltu/xtu).
/// - ー is typed as the vowel the previous unit's readings end in
///   (コーヒー -> ko-o-hi-i) or the literal "-" key when there is no
///   such vowel.
fn jp_merged_step(chars: &[char], i: usize) -> Option<(Vec<String>, usize)> {
    let ch = chars[i];
    if ch == 'っ' || ch == 'ッ' {
        let (readings, span) = jp_unit_readings(chars, i + 1)?;
        let mut doubled: Vec<String> = Vec::with_capacity(readings.len());
        for r in &readings {
            let mut prefix = if r.starts_with("ch") {
                "t".to_string()
            } else if jp_consonant(r.chars().next().unwrap_or('\0')) {
                r.chars().next().unwrap().to_string()
            } else {
                continue;
            };
            prefix.push_str(r);
            doubled.push(prefix);
        }
        return (!doubled.is_empty()).then_some((doubled, span + 1));
    }
    if ch == 'ー' {
        let mut spellings: Vec<String> = Vec::new();
        if i > 0 {
            // the previous unit may be a youon pair: a small kana at
            // i-1 belongs to the base kana before it
            let unit_start = if i >= 2 && youon_vowel(chars[i - 1]).is_some() {
                i - 2
            } else {
                i - 1
            };
            if let Some((readings, _)) = jp_unit_readings(chars, unit_start) {
                for r in &readings {
                    if let Some(v) = r.chars().last().filter(|c| jp_vowel(*c)) {
                        let s = v.to_string();
                        if !spellings.contains(&s) {
                            spellings.push(s);
                        }
                    }
                }
            }
        }
        spellings.push("-".to_string());
        return Some((spellings, 1));
    }
    None
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
            mixed_input: true,
        };
        let (_, tags) = predict("t", "梯", &langs);
        assert_eq!(tags, vec!["ja"]);
        let (_, tags) = predict("n", "nice", &langs);
        assert!(tags.is_empty());
    }

    #[test]
    fn geminate_spellings_double_the_next_onset() {
        let langs = Langs::default();
        // って -> tte; っち folds youon first (ti/ch -> tti/tchi)
        assert!(spellings("きって", &langs).contains(&"kitte".to_string()));
        assert!(spellings("った", &langs).contains(&"tta".to_string()));
        let cha = spellings("っちゃ", &langs);
        assert!(cha.contains(&"tcha".to_string()), "{cha:?}");
        assert!(cha.contains(&"ttya".to_string()), "{cha:?}");
        // matcha is reachable: the labeler can extend "mat" -> c
        let (letters, tags) = predict("mat", "まっちゃ", &langs);
        assert!(letters.contains(&'c'), "{letters:?}");
        assert_eq!(tags, vec!["ja"]);
    }

    #[test]
    fn geminate_keeps_own_spellings_without_double() {
        let ja = Langs {
            zhcn: false,
            ja: true,
            ko: false,
            en: false,
            mixed_input: true,
        };
        // ん reads n/nn: every onset is n, so no doubled form exists
        // and っ falls back to its own ltu/xtu spellings
        assert_eq!(
            spellings("っん", &ja),
            vec![
                "ltun".to_string(),
                "ltunn".to_string(),
                "xtun".to_string(),
                "xtunn".to_string()
            ]
        );
        // unknown next character (no readings): same fallback
        assert_eq!(
            spellings("っz", &ja),
            vec!["ltuz".to_string(), "xtuz".to_string()]
        );
        // trailing っ keeps its own spellings too
        assert_eq!(
            spellings("すっ", &ja),
            vec!["sultu".to_string(), "suxtu".to_string()]
        );
    }

    #[test]
    fn long_vowel_spellings_follow_previous_unit() {
        let ja = Langs {
            zhcn: false,
            ja: true,
            ko: false,
            en: false,
            mixed_input: true,
        };
        // コーヒー -> ko|o|hi|i (plus the "-" key forms)
        let sp = spellings("コーヒー", &ja);
        assert!(sp.contains(&"koohii".to_string()), "{sp:?}");
        assert!(sp.contains(&"ko-hi-".to_string()), "{sp:?}");
        // youon pairs fold before ー picks its vowel: しゃー extends
        // with a (sha/sya/cya all end in a), never the raw し readings'
        // trailing i
        let sp = spellings("しゃー", &ja);
        assert!(sp.contains(&"shaa".to_string()), "{sp:?}");
        assert!(sp.contains(&"sha-".to_string()), "{sp:?}");
        assert!(!sp.iter().any(|s| s.ends_with('i')), "{sp:?}");
        // no usable previous unit: the literal "-" key only
        assert_eq!(spellings("ー", &ja), vec!["-".to_string()]);
        assert_eq!(spellings("aー", &ja), vec!["a-".to_string()]);
        assert_eq!(spellings("ーー", &ja), vec!["--".to_string()]);
    }

    #[test]
    fn small_e_folds_like_youon() {
        let ja = Langs {
            zhcn: false,
            ja: true,
            ko: false,
            en: false,
            mixed_input: true,
        };
        // しぇ -> she (plus the cye/sye fold of the other readings)
        let sp = spellings("しぇ", &ja);
        assert!(sp.contains(&"she".to_string()), "{sp:?}");
        assert!(
            sp.contains(&"sye".to_string()) && sp.contains(&"cye".to_string()),
            "{sp:?}"
        );
        // チェック -> chekku/tyekku: the fold feeds the geminate merge
        let sp = spellings("チェック", &ja);
        assert!(sp.contains(&"chekku".to_string()), "{sp:?}");
        assert!(sp.contains(&"tyekku".to_string()), "{sp:?}");
        // ー after a small-e pair predicts the folded vowel
        let sp = spellings("チェー", &ja);
        assert!(sp.contains(&"che-".to_string()), "{sp:?}");
        assert!(!sp.iter().any(|s| s.ends_with('i')), "{sp:?}");
    }
}
