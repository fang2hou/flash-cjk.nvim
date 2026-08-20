-- Korean (Hangul) engine. Two input interpretations are matched
-- simultaneously: romanization prefixes (Revised Romanization plus
-- common McCune-Reischauer spellings: gim/kim, bak/pak, ri/lee) and
-- two-set (두벌식) keyboard sequences (dkssud -> 안녕).
--
-- Syllables are combinatorially encoded (L*588 + V*28 + T), so every
-- matcher emits code-point range classes ([가-깣]) instead of character
-- lists. Jamo tables live in data.json, 1-based, ordered like the
-- Unicode Jamo blocks (L from U+1100, V from U+1161, T from U+11A7);
-- nil entries are the tense jamo plain lowercase typing cannot produce.
-- Hand-written facts are verified by M.self_check (tests/run.lua) --
-- never in a user's runtime.

local jamo = require("flash-cjk.lang").data("ko")
local L_ROMA, V_ROMA, T_ROMA = jamo.l_roma, jamo.v_roma, jamo.t_roma
local L_KEYS, V_KEYS, T_KEYS = jamo.l_keys, jamo.v_keys, jamo.t_keys

local M = {}

local SYL_BASE = 0xAC00
local MAX_SEG = 4 -- max letters per Korean segment

---Decomposes a precomposed Hangul syllable into 0-based (l, v, t).
---@param ch string single character
---@return number l, number v, number t
local function decompose(ch)
	local cp = vim.fn.char2nr(ch) - SYL_BASE
	return math.floor(cp / 588), math.floor((cp % 588) / 28), cp % 28
end

local function range_class(cps)
	table.sort(cps)
	local parts = {}
	local run_start, run_end = cps[1], cps[1]
	for i = 2, #cps + 1 do
		local cp = cps[i]
		if cp == run_end + 1 then
			run_end = cp
		else
			local first, last = vim.fn.nr2char(run_start), vim.fn.nr2char(run_end)
			parts[#parts + 1] = first == last and first or (first .. "-" .. last)
			run_start, run_end = cp, cp
		end
	end
	-- one class can hold several runs: [가-깣다-둣]
	return "[" .. table.concat(parts) .. "]"
end

local function add_prefix(dict, roma, cp)
	for len = 1, math.min(MAX_SEG, #roma) do
		local prefix = roma:sub(1, len)
		local cps = dict[prefix]
		if not cps then
			cps = {}
			dict[prefix] = cps
		end
		cps[#cps + 1] = cp
	end
end

local function key_seq(l, v, t)
	local l_key, v_key, t_key = L_KEYS[l + 1], V_KEYS[v + 1], T_KEYS[t + 1]
	if not l_key or not v_key or (t > 0 and not t_key) then
		return nil
	end
	return l_key .. v_key .. (t > 0 and t_key or "")
end

local classes = nil ---@type table<string,string>?

local function build()
	local built = {}
	for l = 0, 18 do
		for v = 0, 20 do
			for t = 0, 27 do
				local cp = SYL_BASE + l * 588 + v * 28 + t
				local v_roma, t_roma = V_ROMA[v + 1], T_ROMA[t + 1]
				for _, l_roma in ipairs(L_ROMA[l + 1]) do
					add_prefix(built, l_roma .. v_roma .. t_roma, cp)
				end
				local seq = key_seq(l, v, t)
				if seq then
					add_prefix(built, seq, cp)
				end
			end
		end
	end
	for prefix, cps in pairs(built) do
		built[prefix] = range_class(cps)
	end
	return built
end

---Returns the vim regex fragment for a 1-4 letter Korean prefix
---(romaji or two-set keys), or nil when nothing matches it.
---@param prefix string
---@return string?
function M.pattern(prefix)
	classes = classes or build()
	return classes[prefix]
end

---True for lone vowel letters (complete syllables on their own:
---아=a, 이=i...). Valid mid-pattern; single consonant prefixes only
---make sense as the last, unfinished segment.
function M.vowel_letter(c)
	return c == "a" or c == "e" or c == "i" or c == "o" or c == "u"
end

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
				for _, l_roma in ipairs(L_ROMA[l + 1]) do
					spellings[#spellings + 1] = l_roma .. V_ROMA[v + 1] .. T_ROMA[t + 1]
				end
				local seq = key_seq(l, v, t)
				if seq then
					spellings[#spellings + 1] = seq
				end
			else
				spellings = { ch }
			end
		end
		local expanded = {}
		for _, str in ipairs(strs) do
			for _, spelling in ipairs(spellings) do
				if #expanded < cap then
					expanded[#expanded + 1] = str .. spelling
				end
			end
		end
		strs = expanded
		i = i + size
	end
	return strs
end

-- Hand-written facts, asserted by tests/run.lua.
local function assert_eq(actual, expected, what)
	if actual ~= expected then
		error(
			string.format(
				"ko.lua self-check failed: %s: got %s, want %s",
				what,
				tostring(actual),
				tostring(expected)
			)
		)
	end
end

local function self_check()
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
	assert_eq(key_seq(2, 6, 21), "sud", "녕 = s·u·d") -- guards T_KEYS alignment
	assert_eq(key_seq(3, 0, 0), "ek", "다 = e·k")
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

M.self_check = self_check

return M
