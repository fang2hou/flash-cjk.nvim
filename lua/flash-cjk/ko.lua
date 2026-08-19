-- Korean (Hangul) support for flash-cjk.
-- Two input interpretations are matched simultaneously:
--   * romanization prefixes (Revised Romanization + common
--     McCune-Reischauer variants: gim/kim, bak/pak, ri/lee, tae/dae)
--   * two-set (두벌식) keyboard sequences (dkssud -> 안녕)
--
-- Every matcher emits code-point *range* classes ([가-깣]) because
-- Hangul syllables are combinatorially encoded: L*588 + V*28 + T.
-- Sino-graphic hand-written jamo tables proved error-prone, so the
-- tables below are aligned by 0-based L/V/T index and cross-checked
-- by self_check() at load time.

local M = {}

local SYL_BASE = 0xAC00

---Decomposes a precomposed Hangul syllable into 0-based (l, v, t).
---@param ch string single character
---@return number l, number v, number t
local function decompose(ch)
	local cp = vim.fn.char2nr(ch) - SYL_BASE
	return math.floor(cp / 588), math.floor((cp % 588) / 28), cp % 28
end

-- Romanization (Revised Romanization; initials carry McCune-Reischauer
-- variants for the ambiguous consonants), indexed by 0-based L/V/T.
local L_ROMA = {
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
}
local V_ROMA = {
	"a", "ae", "ya", "yae", "eo", "e", "yeo", "ye", "o", "wa", "wae", "oe", "yo",
	"u", "wo", "we", "wi", "yu", "eu", "ui", "i",
}
local T_ROMA = {
	"", "k", "k", "ks", "n", "nj", "nh", "t", "l", "lg", "lm", "lb", "ls", "lt",
	"lp", "lh", "m", "p", "ps", "s", "s", "ng", "t", "t", "k", "t", "p", "t",
}

-- Two-set key sequences by the same 0-based L/V/T index.
-- nil entries are the tense (shift) jamo that plain lowercase typing
-- cannot produce; those syllables are still reachable via romanization.
local L_KEYS = {
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
}
local V_KEYS = {
	[0] = "k", "o", "i", nil, "j", "p", "u", nil, "h", "hk", "ho", "hl", "y",
	"n", "nj", "np", "nl", "b", "m", "ml", "l",
}
local T_KEYS = {
	[0] = "", "r", nil, "rt", "s", "sw", "sg", "e", "f", "fr", "fa", "fq",
	"ft", "fx", "fv", "fg", "a", "q", "qt", "t", nil, "d", "w", "c", "z", "x",
	"v", "g",
}

-- Exported for scripts/export_rs.lua, which mirrors these tables into
-- Rust; the Lua arrays remain the single source of truth.
M.jamo = {
	l_roma = L_ROMA,
	v_roma = V_ROMA,
	t_roma = T_ROMA,
	l_keys = L_KEYS,
	v_keys = V_KEYS,
	t_keys = T_KEYS,
}

-- ------------------------------------------------------------------
-- prefix tables: romaji / key prefix -> regex range class

local MAX_SEG = 4 -- max letters per Korean segment

local built = nil ---@type table<string,string>?

local function range_class(cps)
	table.sort(cps)
	local parts = {}
	local s, e = cps[1], cps[1]
	for i = 2, #cps + 1 do
		local cp = cps[i]
		if cp == e + 1 then
			e = cp
		else
			local x, y = vim.fn.nr2char(s), vim.fn.nr2char(e)
			parts[#parts + 1] = x == y and x or (x .. "-" .. y)
			s, e = cp, cp
		end
	end
	-- one character class can hold several ranges: [가-깣다-둣]
	return "[" .. table.concat(parts) .. "]"
end

local function add_prefix(dict, roma, cp)
	local maxp = math.min(MAX_SEG, #roma)
	for p = 1, maxp do
		local k = roma:sub(1, p)
		local set = dict[k]
		if not set then
			set = {}
			dict[k] = set
		end
		set[#set + 1] = cp
	end
end

local function key_seq(l, v, t)
	local lk, vk, tk = L_KEYS[l], V_KEYS[v], T_KEYS[t]
	if not lk or not vk or (t > 0 and not tk) then
		return nil
	end
	return lk .. vk .. (t > 0 and tk or "")
end

local function build()
	built = {}
	for l = 0, 18 do
		for v = 0, 20 do
			for t = 0, 27 do
				local cp = SYL_BASE + l * 588 + v * 28 + t
				local vroma, troma = V_ROMA[v + 1], T_ROMA[t + 1]
				for _, lr in ipairs(L_ROMA[l + 1]) do
					add_prefix(built, lr .. vroma .. troma, cp)
				end
				local ks = key_seq(l, v, t)
				if ks then
					add_prefix(built, ks, cp)
				end
			end
		end
	end
	for k, set in pairs(built) do
		built[k] = range_class(set)
	end
end

---Returns the vim regex fragment for a 1-4 letter Korean prefix
---(romaji or two-set keys), or nil when nothing matches it.
---@param prefix string
---@return string?
function M.pattern(prefix)
	if not built then
		build()
	end
	return built[prefix]
end

---True for lone vowel letters (complete syllables on their own:
---아=a, 이=i...). Valid mid-pattern; single consonant prefixes only
---make sense as the last, unfinished segment.
function M.vowel_letter(c)
	return c == "a" or c == "e" or c == "i" or c == "o" or c == "u"
end

-- ------------------------------------------------------------------
-- labeler support: all spellings a text could have been typed as

local char_size = require("flash-cjk.util").char_size

---All romaji and two-set key spellings of the given text.
---@param text string
---@param cap integer? max number of returned strings
---@return string[]
function M.strs(text, cap)
	cap = cap or 64
	local strs = { "" }
	local i = 1
	while i <= #text do
		local size = char_size(text, i)
		local ch = string.sub(text, i, i + size - 1)
		local spellings
		if size == 1 then
			spellings = { ch }
		else
			local cp = vim.fn.char2nr(ch)
			if cp >= SYL_BASE and cp <= 0xD7A3 then
				local l, v, t = decompose(ch)
				spellings = {}
				for _, lr in ipairs(L_ROMA[l + 1]) do
					spellings[#spellings + 1] = lr .. V_ROMA[v + 1] .. T_ROMA[t + 1]
				end
				local ks = key_seq(l, v, t)
				if ks then
					spellings[#spellings + 1] = ks
				end
			else
				spellings = { ch }
			end
		end
		local next = {}
		for _, s in ipairs(strs) do
			for _, r in ipairs(spellings) do
				if #next < cap then
					next[#next + 1] = s .. r
				end
			end
		end
		strs = next
		i = i + size
	end
	return strs
end

-- ------------------------------------------------------------------
-- self-checks: hand-written facts are asserted, not trusted

local function assert_eq(actual, expected, what)
	if actual ~= expected then
		error(string.format("ko.lua self-check failed: %s: got %s, want %s", what, tostring(actual), tostring(expected)))
	end
end

local function self_check()
	-- decomposition samples (0-based indices)
	assert_eq(#L_ROMA, 19, "19 initials in L_ROMA")
	assert_eq(#V_ROMA, 21, "21 medials in V_ROMA")
	assert_eq(#T_ROMA, 28, "28 finals in T_ROMA")
	local l, v, t = decompose("김")
	assert_eq(l .. "," .. v .. "," .. t, "0,20,16", "김 = ㄱ,ㅣ,ㅁ")
	l, v, t = decompose("교")
	assert_eq(t, 0, "교 has no final")
	l, v, t = decompose("앉")
	assert_eq(t, 5, "앉 final is ㄵ (t index 5)")
	-- two-set key sequences
	assert_eq(key_seq(11, 0, 4), "dks", "안 = dk·s") -- ㅇ,d + ㅏ,k + ㄴ,s
	assert_eq(key_seq(11, 0, 5), "dksw", "앉 = dk·sw") -- ㄵ = ㄴ+ㅈ = s·w
	assert_eq(key_seq(18, 0, 0), "gk", "하 = g·k")
	assert_eq(key_seq(2, 6, 21), "sud", "녕 = s·u·d") -- ㄴ,ㅕ,ㅇ -- guards T_KEYS alignment
	assert_eq(key_seq(3, 0, 0), "ek", "다 = e·k") -- ㄷ = e
	-- tense jamo have no lowercase two-set key
	assert_eq(key_seq(1, 0, 0), nil, "까 needs shift")
	-- romanization samples
	local function roma_of(ch, variant)
		local li, vi, ti = decompose(ch)
		return L_ROMA[li + 1][variant or 1] .. V_ROMA[vi + 1] .. T_ROMA[ti + 1]
	end
	assert_eq(roma_of("안"), "an", "안 = an")
	assert_eq(roma_of("김"), "gim", "김 = gim (RR)")
	assert_eq(roma_of("김", 2), "kim", "김 = kim (MR)")
	assert_eq(roma_of("학"), "hak", "학 = hak")
	assert_eq(roma_of("교"), "gyo", "교 = gyo")
	assert_eq(roma_of("앉"), "anj", "앉 = anj")
	assert_eq(roma_of("녕"), "nyeong", "녕 = nyeong")
	assert_eq(roma_of("울"), "ul", "울 = ul")
	assert_eq(roma_of("한"), "han", "한 = han")
end
self_check()

return M
