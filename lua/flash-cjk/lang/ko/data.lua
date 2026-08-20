-- Korean jamo tables, aligned by 0-based L/V/T index. Source of truth
-- for the engine (lang/ko/init.lua) and for the Rust mirror
-- (scripts/export_rs.lua reads ko.jamo, which points here).
return {
	l_roma = {
	{ "g", "k" }, -- ㄱ
	{ "kk" }, -- ㄲ
	{ "n" }, -- ㄴ
	{ "d", "t" }, -- ㄷ
	{ "tt" }, -- ㄸ
	{ "r", "l" }, -- ㄹ
	{ "m" }, -- ㅁ
	{ "b", "p" }, -- ㅂ
	{ "pp" }, -- ㅃ
	{ "s" }, -- ㅅ
	{ "ss" }, -- ㅆ
	{ "" }, -- ㅇ (silent initial)
	{ "j" }, -- ㅈ
	{ "jj" }, -- ㅉ
	{ "ch" }, -- ㅊ
	{ "k" }, -- ㅋ
	{ "t" }, -- ㅌ
	{ "p" }, -- ㅍ
	{ "h" }, -- ㅎ
	},
	v_roma = {
	"a", "ae", "ya", "yae", "eo", "e", "yeo", "ye", "o", "wa", "wae", "oe", "yo",
	"u", "wo", "we", "wi", "yu", "eu", "ui", "i",
	},
	t_roma = {
	"", "k", "k", "ks", "n", "nj", "nh", "t", "l", "lg", "lm", "lb", "ls", "lt",
	"lp", "lh", "m", "p", "ps", "s", "s", "ng", "t", "t", "k", "t", "p", "t",
	},
	l_keys = {
	[0] = "r", -- ㄱ
	nil, -- ㄲ (shift)
	"s", -- ㄴ
	"e", -- ㄷ
	nil, -- ㄸ (shift)
	"f", -- ㄹ
	"a", -- ㅁ
	"q", -- ㅂ
	nil, -- ㅃ (shift)
	"t", -- ㅅ
	nil, -- ㅆ (shift)
	"d", -- ㅇ
	"w", -- ㅈ
	nil, -- ㅉ (shift)
	"c", -- ㅊ
	"z", -- ㅋ
	"x", -- ㅌ
	"v", -- ㅍ
	"g", -- ㅎ
	},
	v_keys = {
	[0] = "k", "o", "i", nil, "j", "p", "u", nil, "h", "hk", "ho", "hl", "y",
	"n", "nj", "np", "nl", "b", "m", "ml", "l",
	},
	t_keys = {
	[0] = "", "r", nil, "rt", "s", "sw", "sg", "e", "f", "fr", "fa", "fq",
	"ft", "fx", "fv", "fg", "a", "q", "qt", "t", nil, "d", "w", "c", "z", "x",
	"v", "g",
	},
}
