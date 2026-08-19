//! Character-set matchers used by segments.

/// A set of characters a single text position can be matched against.
#[derive(Debug, Clone)]
pub enum CharSet {
    /// A single character; `case_insensitive` also matches the other case
    /// (used for the literal `alpha` class `[tT]`).
    Single { c: char, case_insensitive: bool },
    /// An arbitrary set of characters, stored as sorted code points.
    Sorted(Vec<u32>),
    /// Inclusive code point ranges (Korean syllable blocks).
    Ranges(Vec<(u32, u32)>),
}

impl CharSet {
    pub fn single(c: char) -> Self {
        CharSet::Single {
            c,
            case_insensitive: false,
        }
    }

    pub fn single_ci(c: char) -> Self {
        CharSet::Single {
            c,
            case_insensitive: true,
        }
    }

    /// Builds a sorted set from a raw character string (generated data).
    pub fn from_chars(s: &str) -> Self {
        let mut cps: Vec<u32> = s.chars().map(|c| c as u32).collect();
        cps.sort_unstable();
        cps.dedup();
        CharSet::Sorted(cps)
    }

    pub fn ranges(ranges: Vec<(u32, u32)>) -> Self {
        CharSet::Ranges(ranges)
    }

    #[inline]
    pub fn contains(&self, c: char) -> bool {
        match self {
            CharSet::Single {
                c: s,
                case_insensitive,
            } => {
                if *s == c {
                    return true;
                }
                *case_insensitive && c.to_lowercase().eq(s.to_lowercase())
            }
            CharSet::Sorted(cps) => cps.binary_search(&(c as u32)).is_ok(),
            CharSet::Ranges(ranges) => {
                let cp = c as u32;
                // ranges are few (<= 4 per Korean prefix): linear scan beats binary search
                ranges.iter().any(|&(lo, hi)| cp >= lo && cp <= hi)
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn single_exact() {
        let cs = CharSet::single('梯');
        assert!(cs.contains('梯'));
        assert!(!cs.contains('踢'));
    }

    #[test]
    fn single_case_insensitive() {
        let cs = CharSet::single_ci('t');
        assert!(cs.contains('t'));
        assert!(cs.contains('T'));
        assert!(!cs.contains('i'));
    }

    #[test]
    fn sorted_lookup() {
        let cs = CharSet::from_chars("日二丹");
        assert!(cs.contains('日'));
        assert!(cs.contains('二'));
        assert!(cs.contains('丹'));
        assert!(!cs.contains('三'));
    }

    #[test]
    fn range_lookup() {
        let cs = CharSet::ranges(vec![(0xAE30, 0xAE4B)]); // ki prefix: 기(U+AE30)..깋
        assert!(cs.contains('김'));
        assert!(!cs.contains('가'));
        assert!(!cs.contains('힣'));
    }
}
