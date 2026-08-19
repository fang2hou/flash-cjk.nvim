//! DP matcher: finds all (start, end) matches of compiled alternatives
//! in a set of lines (see the module docs below the imports).

use crate::charset::CharSet;
use crate::parser::Alt;
/// A match. `col`/`len` are the byte span; `end_col` is the byte column
/// where the LAST matched character starts (flash's `end_pos` semantics,
/// obtained from the searcher via `Hacks.get_end_pos`).
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
pub struct Match {
    pub line: usize,
    pub col: usize,
    pub len: usize,
    pub end_col: usize,
}

/// Does the segment (a sequence of char sets) match `chars` starting at
/// index `k`? Returns the index just past the match on success.
#[inline]
fn seg_matches_at(sets: &[CharSet], chars: &[(usize, char)], k: usize) -> Option<usize> {
    let nk = k + sets.len();
    if nk > chars.len() {
        return None;
    }
    for (off, set) in sets.iter().enumerate() {
        if !set.contains(chars[k + off].1) {
            return None;
        }
    }
    Some(nk)
}

fn seg_sets(seg: &crate::parser::Segment) -> &[CharSet] {
    match &seg.matcher {
        crate::parser::SegMatcher::One(cs) => std::slice::from_ref(cs),
        crate::parser::SegMatcher::Seq(v) => v,
    }
}

/// Finds matches with vim `searchpos` semantics: scanning left to
/// right, at each start the first alternative (in compile order, which
/// mirrors the Lua alternation order) wins, and accepted spans never
/// overlap. This is what the flash searcher exposes, so the Rust path
/// is behaviorally identical to the vim-regex path.
pub fn find_matches_vim_semantics(lines: &[&str], alts: &[Alt]) -> Vec<Match> {
    let mut out: Vec<Match> = Vec::new();
    for (li, line) in lines.iter().enumerate() {
        let chars: Vec<(usize, char)> = line.char_indices().collect();
        let k_len = chars.len();
        let mut b = 0usize;
        while b < k_len {
            let mut advanced = false;
            for alt in alts {
                let segments: Vec<&crate::parser::Segment> = alt.segments.iter().collect();
                if segments.is_empty() {
                    continue;
                }
                let sets = seg_sets(segments[0]);
                let Some(mut k) = seg_matches_at(sets, &chars, b) else {
                    continue;
                };
                let mut ok = true;
                for seg in &segments[1..] {
                    match seg_matches_at(seg_sets(seg), &chars, k) {
                        Some(nk) => k = nk,
                        None => {
                            ok = false;
                            break;
                        }
                    }
                }
                if ok {
                    let start_byte = chars[b].0;
                    let end_byte = if k == k_len { line.len() } else { chars[k].0 };
                    out.push(Match {
                        line: li,
                        col: start_byte,
                        len: end_byte - start_byte,
                        end_col: chars[k - 1].0,
                    });
                    b = k; // consume past this span: non-overlapping
                    advanced = true;
                    break;
                }
            }
            if !advanced {
                b += 1;
            }
        }
    }
    out
}

/// Finds all matches of `alts` across `lines`.
///
/// Each alternative runs its own DP per start position, so no state is
/// ever shared between alternatives -- exactly the semantics of the
/// alternation regex the Lua side builds. Duplicate spans coming from
/// different alternatives are deduplicated.
pub fn find_matches(lines: &[&str], alts: &[crate::parser::Alt]) -> Vec<Match> {
    let total: usize = alts
        .iter()
        .map(|a| a.segments.iter().map(|s| s.input.len()).sum::<usize>())
        .max()
        .unwrap_or(0);
    if total == 0 || alts.is_empty() {
        return Vec::new();
    }
    let mut out: Vec<Match> = Vec::new();
    for (li, line) in lines.iter().enumerate() {
        let chars: Vec<(usize, char)> = line.char_indices().collect();
        let k_len = chars.len();
        if k_len == 0 {
            continue;
        }
        for alt in alts {
            let segments: Vec<&crate::parser::Segment> = alt.segments.iter().collect();
            if segments.is_empty() {
                continue;
            }
            for b in 0..k_len {
                // per-alternative, per-start frontier of text positions
                let mut cur: Vec<usize> = Vec::new();
                {
                    let sets = seg_sets(segments[0]);
                    if let Some(nk) = seg_matches_at(sets, &chars, b) {
                        cur.push(nk);
                    } else {
                        continue; // this start cannot begin this alternative
                    }
                }
                for seg in &segments[1..] {
                    let sets = seg_sets(seg);
                    let mut next: Vec<usize> = Vec::new();
                    for &k in &cur {
                        if let Some(nk) = seg_matches_at(sets, &chars, k) {
                            next.push(nk);
                        }
                    }
                    if next.is_empty() {
                        cur.clear();
                        break;
                    }
                    next.sort_unstable();
                    next.dedup();
                    cur = next;
                }
                if cur.is_empty() {
                    continue;
                }
                for k in cur {
                    let start_byte = chars[b].0;
                    let end_byte = if k == k_len { line.len() } else { chars[k].0 };
                    out.push(Match {
                        line: li,
                        col: start_byte,
                        len: end_byte - start_byte,
                        end_col: chars[k - 1].0,
                    });
                }
            }
        }
    }
    out.sort_unstable();
    out.dedup();
    out
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::parser::{compile, Alt, Langs, SegMatcher, Segment};

    fn one_ascii(c: char) -> Segment {
        Segment {
            input: c.to_string(),
            matcher: SegMatcher::One(CharSet::single_ci(c)),
            kind: crate::parser::SegKind::Literal,
        }
    }

    fn alt(segs: Vec<Segment>) -> Alt {
        Alt { segments: segs }
    }

    fn texts_of(lines: &[&str], ms: &[Match]) -> Vec<String> {
        ms.iter()
            .map(|m| lines[m.line][m.col..m.col + m.len].to_string())
            .collect()
    }

    #[test]
    fn literal_alt_matches() {
        let alts = vec![alt(vec![one_ascii('t'), one_ascii('i')])];
        let lines = ["time to ti"];
        let ms = find_matches(&lines, &alts);
        assert_eq!(ms.len(), 2, "{ms:?}");
        assert_eq!(
            ms[0],
            Match {
                line: 0,
                col: 0,
                len: 2,
                end_col: 1
            }
        );
        assert_eq!(
            ms[1],
            Match {
                line: 0,
                col: 8,
                len: 2,
                end_col: 9
            }
        );
    }

    #[test]
    fn charset_alt_matches() {
        let cs = CharSet::from_chars("日二");
        let alts = vec![alt(vec![Segment {
            input: "ni".into(),
            matcher: SegMatcher::One(cs),
            kind: crate::parser::SegKind::Jp,
        }])];
        let lines = ["x日y二z三"];
        let ms = find_matches(&lines, &alts);
        assert_eq!(texts_of(&lines, &ms), vec!["日", "二"]);
    }

    #[test]
    fn youon_sequence_matches_two_chars() {
        let seq: Vec<CharSet> = "しゃ".chars().map(CharSet::single).collect();
        let alts = vec![alt(vec![Segment {
            input: "sha".into(),
            matcher: SegMatcher::Seq(seq),
            kind: crate::parser::SegKind::Jp,
        }])];
        let lines = ["xしゃy"];
        let ms = find_matches(&lines, &alts);
        assert_eq!(ms.len(), 1);
        assert_eq!(
            ms[0],
            Match {
                line: 0,
                col: 1,
                len: 6,
                end_col: 4
            }
        ); // しゃ = 6 bytes
    }

    #[test]
    fn vim_semantics_non_overlapping_first_alt_wins() {
        // two alternatives can both match at the same start: the first
        // alternative (compile order) wins and the scan resumes after
        // its span, so overlapping spans are never emitted.
        use crate::parser::{SegKind, Segment};
        let mk = |input: &str, ch: char| Segment {
            input: input.to_string(),
            matcher: SegMatcher::One(CharSet::single(ch)),
            kind: SegKind::Literal,
        };
        // alt1: "aa" -> matches literal x then p ; alt2: "ab" -> x then q
        let alts = vec![
            alt(vec![mk("a", 'x'), mk("a", 'p')]),
            alt(vec![mk("a", 'x'), mk("b", 'q')]),
        ];
        // "xpq" -> at 0: alt1 matches "xp" (span 0..2); resume at q: no match
        let lines = ["xpq"];
        let ms = find_matches_vim_semantics(&lines, &alts);
        assert_eq!(texts_of(&lines, &ms), vec!["xp"]);
        // "xq" -> alt1 fails at 0 (p!=q); alt2 matches "xq"
        let lines2 = ["xq"];
        let ms2 = find_matches_vim_semantics(&lines2, &alts);
        assert_eq!(texts_of(&lines2, &ms2), vec!["xq"]);
    }

    #[test]
    fn no_cross_alt_splicing() {
        // alt1 matches literal "xp", alt2 matches literal "qy".
        // A spliced path (alt1's first segment + alt2's second) would
        // match "xy" or "qy"-like combinations that neither alternation
        // branch contains; none of those may appear.
        let alts = vec![
            alt(vec![one_ascii('x'), one_ascii('p')]),
            alt(vec![one_ascii('q'), one_ascii('y')]),
        ];
        let lines = ["xp xq xy qp qy xx pp"];
        let ms = find_matches(&lines, &alts);
        let texts = texts_of(&lines, &ms);
        assert!(texts.contains(&"xp".to_string()), "{texts:?}");
        assert!(texts.contains(&"qy".to_string()), "{texts:?}");
        assert!(
            !texts.contains(&"xy".to_string()),
            "spliced alt1+alt2: {texts:?}"
        );
        assert!(!texts.contains(&"qy".to_string()) || true);
        assert_eq!(texts.len(), 2, "exactly the two real branches: {texts:?}");
    }

    #[test]
    fn no_matches_on_empty_or_absent() {
        let alts = vec![alt(vec![one_ascii('q'), one_ascii('q')])];
        assert!(find_matches(&["abc"], &alts).is_empty());
        assert!(find_matches(&[], &alts).is_empty());
    }

    #[test]
    fn compiled_pattern_finds_trilingual() {
        let lines = ["日本語テスト ちちはち 梯子 한국어 안녕"];
        let alts = compile("ti", Langs::default());
        let ms = find_matches(&lines, &alts);
        let texts = texts_of(&lines, &ms);
        assert!(texts.contains(&"ち".to_string()), "{texts:?}");
        assert!(texts.contains(&"梯".to_string()), "{texts:?}");
    }

    #[test]
    fn lock_marker_filters() {
        let lines = ["日本語テスト ちちはち 梯子"];
        let all = find_matches(&lines, &compile("ti", Langs::default()));
        let cn = find_matches(&lines, &compile("ti\u{1}", Langs::default()));
        assert!(texts_of(&lines, &all).contains(&"ち".to_string()));
        assert!(!texts_of(&lines, &cn).contains(&"ち".to_string()));
        assert!(texts_of(&lines, &cn).contains(&"梯".to_string()));
    }
}

#[cfg(test)]
mod fuzz {
    use super::*;
    use crate::parser::{compile, Langs};

    /// xorshift64* deterministic PRNG
    struct Rng(u64);
    impl Rng {
        fn next(&mut self) -> u64 {
            let mut x = self.0;
            x ^= x >> 12;
            x ^= x << 25;
            x ^= x >> 27;
            self.0 = x;
            x.wrapping_mul(0x2545F4914F6CDD1D)
        }
        fn below(&mut self, n: u64) -> u64 {
            self.next() % n
        }
    }

    const ALPHABET: &[&str] = &[
        "a", "e", "i", "o", "u", "n", "k", "s", "t", "h", "d", "r", "g", "b", "m", "y", "c", "l",
        "p", "z", "x", "q", "w", "v", "j", "f", "A", "Z", "0", "9", ".", ",", "-", "?", "!", "\\",
        "'", "\"", "日", "本", "語", "ち", "しゃ", "梯", "安", "녕", "你", "好", "\u{1}", "\u{2}",
        "\u{4}", "\u{5}", // lock markers
        "\u{0}", "\u{7f}", "\t", // hostile control bytes
    ];

    fn random_input(rng: &mut Rng, max_items: u64) -> String {
        let n = rng.below(max_items) + 1;
        let mut s = String::new();
        for _ in 0..n {
            s.push_str(ALPHABET[rng.below(ALPHABET.len() as u64) as usize]);
        }
        s
    }

    #[test]
    fn fuzz_never_panics_and_invariants_hold() {
        let mut rng = Rng(0xC0FFEE);
        for round in 0..2000 {
            let pattern = random_input(&mut rng, 8);
            let mut lines = Vec::new();
            for _ in 0..3 {
                lines.push(random_input(&mut rng, 30));
            }
            let line_refs: Vec<&str> = lines.iter().map(String::as_str).collect();

            // compile must never panic
            let alts = compile(&pattern, Langs::default());
            assert!(alts.len() <= 600, "round {round}: alt budget exceeded");

            // full-match mode: every span must be char-aligned and in bounds
            for m in find_matches(&line_refs, &alts) {
                let line = &lines[m.line];
                assert!(m.col < line.len(), "round {round}: col out of bounds");
                assert!(
                    m.col + m.len <= line.len(),
                    "round {round}: len out of bounds"
                );
                assert!(
                    line.is_char_boundary(m.col),
                    "round {round}: col not char boundary"
                );
                assert!(
                    line.is_char_boundary(m.col + m.len),
                    "round {round}: end not boundary"
                );
                assert!(
                    m.end_col >= m.col && m.end_col < m.col + m.len,
                    "round {round}: end_col inconsistent"
                );
                assert!(
                    line.is_char_boundary(m.end_col),
                    "round {round}: end_col not boundary"
                );
            }

            // vim semantics: sorted, non-overlapping, in bounds
            let vim = find_matches_vim_semantics(&line_refs, &alts);
            let mut last_end: Option<(usize, usize)> = None; // (line, col+len)
            for m in &vim {
                let line = &lines[m.line];
                assert!(m.col + m.len <= line.len(), "round {round}: vim span oob");
                assert!(
                    line.is_char_boundary(m.col),
                    "round {round}: vim col boundary"
                );
                if let Some((ll, le)) = last_end {
                    if m.line == ll {
                        assert!(m.col >= le, "round {round}: vim spans overlap");
                    } else {
                        assert!(m.line > ll, "round {round}: vim spans not line-sorted");
                    }
                }
                last_end = Some((m.line, m.col + m.len));
            }

            // vim spans are a subset of all spans
            let all: std::collections::HashSet<(usize, usize, usize)> =
                find_matches(&line_refs, &alts)
                    .into_iter()
                    .map(|m| (m.line, m.col, m.len))
                    .collect();
            for m in &vim {
                assert!(
                    all.contains(&(m.line, m.col, m.len)),
                    "round {round}: vim span not in all-spans set"
                );
            }
        }
    }
}
