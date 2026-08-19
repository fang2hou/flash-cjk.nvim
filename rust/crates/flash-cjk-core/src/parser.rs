//! Pattern segmentation: compiles a typed input pattern into every
//! plausible sequence of segments, mirroring lua/flash-cjk/init.lua's
//! `parser` semantics (segment kinds, vowel whitelisting, alpha-chain
//! rule, mid-input language-lock markers, segmentation budget).

use crate::charset::CharSet;
use crate::data::data;

/// Language flags for one search.
#[derive(Debug, Clone, Copy)]
pub struct Langs {
    pub cn: bool,
    pub jp: bool,
    pub ko: bool,
    pub original: bool,
    pub alpha_mixing: bool,
}

impl Default for Langs {
    fn default() -> Self {
        Langs {
            cn: true,
            jp: true,
            ko: true,
            original: true,
            alpha_mixing: true,
        }
    }
}

#[derive(Debug, PartialEq, Eq, Clone, Copy)]
pub enum SegKind {
    Cn,
    Jp,
    Ko,
    Literal,
}

/// What a segment matches in the text.
#[derive(Debug, Clone)]
pub enum SegMatcher {
    /// exactly one character from the set
    One(CharSet),
    /// a fixed sequence of characters (youon combos: しゃ = し+ゃ)
    Seq(Vec<CharSet>),
}

/// One segment: consumes `input.len()` typed keys and matches text
/// according to `matcher`.
#[derive(Debug, Clone)]
pub struct Segment {
    pub input: String,
    pub matcher: SegMatcher,
    /// Which matcher produced this segment (carries the language flag
    /// the compiler had; used by tests and introspection).
    pub kind: SegKind,
}

/// One interpretation: a full sequence of segments covering the input.
#[derive(Debug, Clone)]
pub struct Alt {
    pub segments: Vec<Segment>,
}

/// Internal lock markers (mirror of `MARKER_BYTES` in init.lua; the
/// pressed keys are decoupled from these bytes on the Lua side).
pub const MARKER_CN: char = '\u{1}';
pub const MARKER_JP: char = '\u{2}';
pub const MARKER_KO: char = '\u{4}';
pub const MARKER_EO: char = '\u{5}';

/// Upper bound on interpretations, mirroring MAX_SEGMENTATIONS.
const MAX_ALTS: usize = 600;

/// Splits a raw pattern (with lock markers) into (clean, lock marker).
/// The rightmost marker wins. Merging the marker with the base language
/// flags happens in `compile` (which knows `base.original`).
pub fn parse_forced(pattern: &str) -> (String, Option<char>) {
    let mut best_pos = 0usize;
    let mut best: Option<char> = None;
    let mut clean = String::with_capacity(pattern.len());
    for (pos, c) in pattern.char_indices() {
        let is_marker = matches!(c, MARKER_CN | MARKER_JP | MARKER_KO | MARKER_EO);
        if is_marker {
            if pos >= best_pos {
                best_pos = pos;
                best = Some(c);
            }
        } else {
            clean.push(c);
        }
    }
    (clean, best)
}

/// Punctuation classes per language (mirror of the Lua comma tables).
fn comma_classes(langs: &Langs) -> Vec<(char, CharSet)> {
    // build from the character strings of the Lua tables
    let cn = [
        ".。", "\\[【", "\\]】", ",，", "?？", ":：", ";；", "'‘’", "\"“”",
    ];
    let jp = [",、", ".。", "\\[「『", "\\]」』", "?？", "!！", "-ー‐"];
    let mut out: Vec<(char, CharSet)> = Vec::new();
    let merge = |out: &mut Vec<(char, CharSet)>, key: char, chars: &str| {
        let set = CharSet::from_chars(&chars.replace('\\', ""));
        match out.iter_mut().find(|(k, _)| *k == key) {
            Some((_, existing)) => {
                let CharSet::Sorted(a) = existing else { return };
                let CharSet::Sorted(b) = &set else { return };
                let mut merged = a.clone();
                merged.extend_from_slice(b);
                merged.sort_unstable();
                merged.dedup();
                *existing = CharSet::Sorted(merged);
            }
            None => out.push((key, set)),
        }
    };
    let cn_map = [
        ('.', &cn[0]),
        ('[', &cn[1]),
        (']', &cn[2]),
        (',', &cn[3]),
        ('?', &cn[4]),
        (':', &cn[5]),
        (';', &cn[6]),
        ('\'', &cn[7]),
        ('"', &cn[8]),
    ];
    if langs.cn {
        for (k, v) in cn_map {
            merge(&mut out, k, v);
        }
    }
    let jp_map = [
        (',', &jp[0]),
        ('.', &jp[1]),
        ('[', &jp[2]),
        (']', &jp[3]),
        ('?', &jp[4]),
        ('!', &jp[5]),
        ('-', &jp[6]),
    ];
    if langs.jp {
        for (k, v) in jp_map {
            merge(&mut out, k, v);
        }
    }
    out
}

fn is_comma_key(c: char, commas: &[(char, CharSet)]) -> bool {
    // ASCII keys only; the class content is matched at text level
    commas.iter().any(|(k, _)| *k == c)
}

fn jp_vowel(c: char) -> bool {
    matches!(c, 'a' | 'e' | 'i' | 'o' | 'u')
}

struct Compiler<'a> {
    langs: Langs,
    commas: Vec<(char, CharSet)>,
    alts: Vec<Alt>,
    d: &'a crate::data::Data,
}

impl<'a> Compiler<'a> {
    fn push(&mut self, segs: Vec<Segment>) {
        self.alts.push(Alt { segments: segs });
    }

    /// Mirrors M.parser: enumerate segmentations of `rest`, extending `segs`.
    fn parse(&mut self, rest: &str, mut segs: Vec<Segment>, alpha_ok: bool) {
        if self.alts.len() >= MAX_ALTS {
            return;
        }
        let mut chars = rest.chars();
        let Some(first) = chars.next() else {
            self.push(segs);
            return;
        };
        let second = chars.next().unwrap_or('\0');
        let third = chars.next().unwrap_or('\0');
        let tail2 = &rest[first.len_utf8()..];
        // second/third may be the '\0' sentinel: never slice past the end
        let tail3 = rest
            .get(first.len_utf8() + second.len_utf8()..)
            .unwrap_or("");
        let tail4_at = first.len_utf8() + second.len_utf8() + third.len_utf8();

        if first.is_ascii_lowercase() {
            let alpha_allowed = self.langs.original && (self.langs.alpha_mixing || alpha_ok);
            if second == '\0' {
                // last key: alpha / singlepin / jp1 / ko1
                let f1 = first.to_string();
                if alpha_allowed {
                    let mut s = segs.clone();
                    s.push(Segment {
                        input: first.to_string(),
                        matcher: SegMatcher::One(CharSet::single_ci(first)),
                        kind: SegKind::Literal,
                    });
                    self.parse("", s, alpha_ok);
                }
                if self.langs.cn {
                    if let Some(cs) = self.d.cn_char1.get(first.encode_utf8(&mut [0u8; 4])) {
                        let mut s = segs.clone();
                        s.push(Segment {
                            input: first.to_string(),
                            matcher: SegMatcher::One(cs.clone()),
                            kind: SegKind::Cn,
                        });
                        self.parse("", s, false);
                    }
                }
                if self.langs.jp {
                    if let Some(cs) = self.d.jp_p1.get(f1.as_str()) {
                        let mut s = segs.clone();
                        s.push(Segment {
                            input: first.to_string(),
                            matcher: SegMatcher::One(cs.clone()),
                            kind: SegKind::Jp,
                        });
                        self.parse("", s, false);
                    }
                }
                if self.langs.ko {
                    if let Some(cs) = self.d.ko.get(rest) {
                        let mut s = segs;
                        s.push(Segment {
                            input: rest.to_string(),
                            matcher: SegMatcher::One(cs.clone()),
                            kind: SegKind::Ko,
                        });
                        self.parse("", s, false);
                    }
                }
            } else if second.is_ascii_alphabetic() {
                let f2 = first.to_string();
                let two: String = [first, second].iter().collect();
                let three: String = [first, second, third].iter().collect();
                // cn flypy (2 keys)
                if self.langs.cn && self.d.cn_char2.contains_key(two.as_str()) {
                    let cs = self.d.cn_char2[two.as_str()].clone();
                    let mut s = segs.clone();
                    s.push(Segment {
                        input: two.clone(),
                        matcher: SegMatcher::One(cs),
                        kind: SegKind::Cn,
                    });
                    self.parse(tail3, s, false);
                }
                // jp 3-letter
                if self.langs.jp && third.is_ascii_alphabetic() {
                    if let Some(cs) = self.d.jp_p3_class.get(three.as_str()) {
                        let cs = cs.clone();
                        let mut s = segs.clone();
                        s.push(Segment {
                            input: three.clone(),
                            matcher: SegMatcher::One(cs),
                            kind: SegKind::Jp,
                        });
                        let tail4 = rest.get(tail4_at..).unwrap_or("");
                        self.parse(tail4, s, false);
                    }
                    for lit in self.d.jp_p3_lit.get(three.as_str()).into_iter().flatten() {
                        let seq: Vec<CharSet> = lit.chars().map(CharSet::single).collect();
                        let mut s = segs.clone();
                        s.push(Segment {
                            input: three.clone(),
                            matcher: SegMatcher::Seq(seq),
                            kind: SegKind::Jp,
                        });
                        let tail4 = rest.get(tail4_at..).unwrap_or("");
                        self.parse(tail4, s, false);
                    }
                }
                // jp 2-letter
                if self.langs.jp && self.d.jp_p2.contains_key(two.as_str()) {
                    let cs = self.d.jp_p2[two.as_str()].clone();
                    let mut s = segs.clone();
                    s.push(Segment {
                        input: two.clone(),
                        matcher: SegMatcher::One(cs),
                        kind: SegKind::Jp,
                    });
                    self.parse(tail3, s, false);
                }
                // jp 1-letter mid-pattern: vowels + n only
                if self.langs.jp
                    && matches!(first, 'a' | 'e' | 'i' | 'o' | 'u' | 'n')
                    && self.d.jp_p1.contains_key(f2.as_str())
                {
                    let cs = self.d.jp_p1[f2.as_str()].clone();
                    let mut s = segs.clone();
                    s.push(Segment {
                        input: first.to_string(),
                        matcher: SegMatcher::One(cs),
                        kind: SegKind::Jp,
                    });
                    self.parse(tail2, s, false);
                }
                // ko 2-4 letters
                if self.langs.ko {
                    let f3 = first.to_string();
                    for len in (2..=4).rev() {
                        // ko segment keys are ASCII letters; refuse to cut
                        // through multi-byte chars when the pattern holds
                        // non-ASCII text
                        if rest.len() < len || !rest.is_char_boundary(len) {
                            continue;
                        }
                        let seg = &rest[..len];
                        if seg.is_ascii() && seg.chars().count() == len {
                            if let Some(cs) = self.d.ko.get(seg) {
                                let cs = cs.clone();
                                let mut s = segs.clone();
                                s.push(Segment {
                                    input: seg.to_string(),
                                    matcher: SegMatcher::One(cs),
                                    kind: SegKind::Ko,
                                });
                                let tail = &rest[seg.len()..];
                                self.parse(tail, s, false);
                            }
                        }
                    }
                    if jp_vowel(first) && self.d.ko.contains_key(f3.as_str()) {
                        let cs = self.d.ko[f3.as_str()].clone();
                        let mut s = segs.clone();
                        s.push(Segment {
                            input: first.to_string(),
                            matcher: SegMatcher::One(cs),
                            kind: SegKind::Ko,
                        });
                        self.parse(tail2, s, false);
                    }
                }
                // literal alpha
                if alpha_allowed {
                    let mut s = segs.clone();
                    s.push(Segment {
                        input: first.to_string(),
                        matcher: SegMatcher::One(CharSet::single_ci(first)),
                        kind: SegKind::Literal,
                    });
                    self.parse(tail2, s, alpha_ok);
                }
            } else if is_comma_key(second, &self.commas) && alpha_allowed {
                let (_, cs) = self.commas.iter().find(|(k, _)| *k == second).unwrap();
                segs.push(Segment {
                    input: first.to_string(),
                    matcher: SegMatcher::One(CharSet::single_ci(first)),
                    kind: SegKind::Literal,
                });
                segs.push(Segment {
                    input: second.to_string(),
                    matcher: SegMatcher::One(cs.clone()),
                    kind: SegKind::Literal,
                });
                self.parse(tail3, segs, alpha_ok);
            } else if alpha_allowed {
                // alpha + other literal
                let esc = if second == '\\' {
                    "\\\\"
                } else {
                    &second.to_string()
                };
                let _ = esc; // Lua escapes for the regex; here the raw char is matched
                segs.push(Segment {
                    input: first.to_string(),
                    matcher: SegMatcher::One(CharSet::single_ci(first)),
                    kind: SegKind::Literal,
                });
                segs.push(Segment {
                    input: second.to_string(),
                    matcher: SegMatcher::One(CharSet::single(second)),
                    kind: SegKind::Literal,
                });
                self.parse(tail3, segs, alpha_ok);
            }
        } else if is_comma_key(first, &self.commas) {
            let (_, cs) = self.commas.iter().find(|(k, _)| *k == first).unwrap();
            segs.push(Segment {
                input: first.to_string(),
                matcher: SegMatcher::One(cs.clone()),
                kind: SegKind::Literal,
            });
            self.parse(tail2, segs, alpha_ok);
        } else {
            // "other": match the character literally
            segs.push(Segment {
                input: first.to_string(),
                matcher: SegMatcher::One(CharSet::single(first)),
                kind: SegKind::Literal,
            });
            self.parse(tail2, segs, alpha_ok);
        }
    }
}

/// Compiles a raw pattern (lock markers included) into interpretations.
pub fn compile(pattern: &str, base: Langs) -> Vec<Alt> {
    let (clean, marker) = parse_forced(pattern);
    // mirrors forced_langs in init.lua: the lock turns the other language
    // matchers off but keeps the base `original` (literal) flag; an eo
    // lock forces literal matching on.
    let langs = marker.map_or(base, |m| Langs {
        cn: m == MARKER_CN,
        jp: m == MARKER_JP,
        ko: m == MARKER_KO,
        original: m == MARKER_EO || base.original,
        alpha_mixing: base.alpha_mixing,
    });
    let mut compiler = Compiler {
        langs,
        commas: comma_classes(&langs),
        alts: Vec::new(),
        d: data(),
    };
    compiler.parse(clean.as_str(), Vec::new(), true);
    if compiler.alts.is_empty() {
        // no interpretation: match the literal clean input, like the
        // \V fallback on the Lua side
        let segs: Vec<Segment> = clean
            .chars()
            .map(|c| Segment {
                input: c.to_string(),
                matcher: SegMatcher::One(CharSet::single(c)),
                kind: SegKind::Literal,
            })
            .collect();
        compiler.alts.push(Alt { segments: segs });
    }
    compiler.alts
}

impl Segment {
    pub fn matcher_kind(&self) -> SegKind {
        self.kind
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn forced_parsing() {
        let (clean, m) = parse_forced("ti\u{1}");
        assert_eq!(clean, "ti");
        assert_eq!(m, Some(MARKER_CN));
        let (clean, m) = parse_forced("ti\u{1}\u{2}");
        assert_eq!(clean, "ti");
        assert_eq!(m, Some(MARKER_JP), "rightmost marker wins");
        let (clean, forced) = parse_forced("ti");
        assert_eq!(clean, "ti");
        assert!(forced.is_none());
    }

    #[test]
    fn compile_basic_alt_counts() {
        // "ni" with all languages: pinyin ni | alpha n+i | singlepin tail? ...
        let alts = compile("ni", Langs::default());
        assert!(!alts.is_empty(), "at least the pinyin interpretation");
        let has_pinyin = alts
            .iter()
            .any(|a| a.segments.len() == 1 && a.segments[0].input == "ni");
        assert!(has_pinyin, "flypy ni segment present");
        let has_alpha = alts
            .iter()
            .any(|a| a.segments.len() == 2 && a.segments.iter().all(|s| s.input.len() == 1));
        assert!(has_alpha, "literal alpha chain present");
    }

    #[test]
    fn compile_budget_caps_long_inputs() {
        let alts = compile("kanjixk", Langs::default());
        assert!(alts.len() <= MAX_ALTS);
    }

    #[test]
    fn forced_lock_filters_segments() {
        // with the jp lock, no cn segments should appear
        let alts = compile("ni\u{2}", Langs::default());
        assert!(!alts.is_empty());
        for alt in &alts {
            for seg in &alt.segments {
                assert_ne!(seg.matcher_kind(), crate::parser::SegKind::Cn);
            }
        }
    }
}
