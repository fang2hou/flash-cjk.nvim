-- Matching domain: segmentation parser, punctuation classes, language
-- lock markers and the mixed-mode pattern compiler. Independent of
-- flash.nvim -- init.lua drives these through jump/remote/setup.

local zhcn = require("flash-cjk.zhcnData")
local config = require("flash-cjk.config")

local M = {}

local ja ---@type table?
local function get_ja()
	if ja == nil then
		ja = require("flash-cjk.ja")
	end
	return ja
end

local ko ---@type table?
local function get_ko()
	if ko == nil then
		ko = require("flash-cjk.ko")
	end
	return ko
end

-- Upper bound on the number of pattern interpretations kept per keystroke.
-- Romaji segments are 1-3 letters long, so the number of possible
-- segmentations grows quickly; longer inputs degrade gracefully instead.
local MAX_SEGMENTATIONS = 600

-- ------------------------------------------------------------------
-- punctuation

local comma_cache = {} ---@type table<string, table<string,string>>
-- The cache key encodes the cn/jp flags, the tables' only inputs, so
-- entries self-invalidate when setup() changes the enabled languages.

-- Effective punctuation map: each enabled language contributes its own
local function merge_class(a, b)
	if not a then
		return b
	end
	if not b then
		return a
	end
	return "[" .. string.sub(a, 2, -2) .. string.sub(b, 2, -2) .. "]"
end

local function comma_map(langs)
	local key = (langs.cn and "z" or "-") .. (langs.jp and "j" or "-")
	local map = comma_cache[key]
	if not map then
		map = {}
		local cn_tbl = langs.cn and zhcn.comma or {}
		local ja_tbl = langs.jp and get_ja().comma or {}
		for _, src in ipairs({ cn_tbl, ja_tbl }) do
			for k, v in pairs(src) do
				map[k] = merge_class(map[k], v)
			end
		end
		comma_cache[key] = map
	end
	return map
end

-- ------------------------------------------------------------------
-- pattern building

-- Shallow copy including the `_alpha` bookkeeping field.
local function copy(tbl)
	local c = {}
	for k, v in pairs(tbl) do
		c[k] = v
	end
	return c
end

local function merge_table(tab1, tab2)
	for i = 1, #tab2 do
		table.insert(tab1, tab2[i])
	end
	return tab1
end

local function make_nodes(comma)
	return {
		alpha = function(str)
			return "[" .. str .. string.upper(str) .. "]"
		end,
		pinyin = function(str)
			return zhcn.char2patterns[str]
		end,
		comma = function(str)
			return comma[str]
		end,
		singlepin = function(str)
			return zhcn.char1patterns[str]
		end,
		jp = function(str)
			return get_ja().pattern(str)
		end,
		ko = function(str)
			return get_ko().pattern(str)
		end,
		other = function(str)
			str = zhcn.escape[str] or str
			return str
		end,
	}
end

local function regex(segments, comma)
	local nodes = make_nodes(comma)
	local regexs = {}
	for _, v in ipairs(segments) do
		regexs[#regexs + 1] = nodes[v.type](v.str)
	end
	return table.concat(regexs)
end

-- Splits the input into every plausible sequence of segments.
-- A segment is one of: a literal letter (alpha), a 2-key flypy code
-- (pinyin), a single pinyin first letter (singlepin), a 1-3 letter
-- romaji prefix (jp), a punctuation key (comma) or any other character.
---@param str string
---@param prefix table? partial segmentation
---@param ctx {count: integer, langs: table<string,boolean>, comma: table<string,string>}
---@return table
local function parser(str, prefix, ctx)
	prefix = prefix or {}
	if ctx == nil then
		local flags = config.lang_flags()
		ctx = { count = 0, langs = flags, comma = comma_map(flags) }
	end
	if ctx.count >= MAX_SEGMENTATIONS then
		return {}
	end
	local firstchar = string.sub(str, 1, 1)
	local secondchar = string.sub(str, 2, 2)
	local thirdchar = string.sub(str, 3, 3)
	local chars = {}
	for k, _ in pairs(ctx.comma) do
		table.insert(chars, k)
	end
	if firstchar == "" then
		ctx.count = ctx.count + 1
		return { prefix }
	elseif string.match(firstchar, "%l") then
		local results = {}
		if secondchar == "" then
			if ctx.langs.en and (ctx.langs.alpha_mixing ~= false or prefix._alpha ~= false) then
				local p1 = copy(prefix)
				p1[#p1 + 1] = { str = firstchar, type = "alpha" }
				results = merge_table(results, parser("", p1, ctx))
			end
			if ctx.langs.cn then
				local p2 = copy(prefix)
				p2[#p2 + 1] = { str = firstchar, type = "singlepin" }
				results = merge_table(results, parser("", p2, ctx))
			end
			if ctx.langs.jp and get_ja().pattern(firstchar) then
				local p3 = copy(prefix)
				p3[#p3 + 1] = { str = firstchar, type = "jp" }
				results = merge_table(results, parser("", p3, ctx))
			end
			if ctx.langs.ko and get_ko().pattern(firstchar) then
				local p4 = copy(prefix)
				p4[#p4 + 1] = { str = firstchar, type = "ko" }
				results = merge_table(results, parser("", p4, ctx))
			end
			return results
		elseif string.match(secondchar, "%a") then
			-- longest / most specific segments first: when the segmentation
			-- budget runs out on long inputs, the informative branches
			-- (pinyin, romaji) survive instead of the literal alpha ones
			--
			-- Literal letters and language segments do not mix within one
			-- interpretation (prefix._alpha): mixed chains multiply the
			-- alternatives and each giant CJK character class makes vim's
			-- regex execution measurably slower.
			if ctx.langs.cn and zhcn.char2patterns[firstchar .. secondchar] then
				local p = copy(prefix)
				p._alpha = false
				p[#p + 1] = { str = firstchar .. secondchar, type = "pinyin" }
				results = merge_table(results, parser(string.sub(str, 3), p, ctx))
			end
			if ctx.langs.jp then
				local J = get_ja()
				local two = firstchar .. secondchar
				local three = two .. thirdchar
				if string.match(thirdchar, "%a") and J.pattern(three) then
					local pj = copy(prefix)
					pj._alpha = false
					pj[#pj + 1] = { str = three, type = "jp" }
					results = merge_table(results, parser(string.sub(str, 4), pj, ctx))
				end
				if J.pattern(two) then
					local pj = copy(prefix)
					pj._alpha = false
					pj[#pj + 1] = { str = two, type = "jp" }
					results = merge_table(results, parser(string.sub(str, 3), pj, ctx))
				end
				-- Mid-pattern single-letter romaji is only kept for keys that
				-- are complete syllables on their own (vowels + n: あおい, にほんご);
				-- consonant prefixes (ka, tsu...) are always typed to completion,
				-- so they only matter as the last, unfinished segment.
				if vim.list_contains({ "a", "e", "i", "o", "u", "n" }, firstchar) and J.pattern(firstchar) then
					local pj = copy(prefix)
					pj._alpha = false
					pj[#pj + 1] = { str = firstchar, type = "jp" }
					results = merge_table(results, parser(string.sub(str, 2), pj, ctx))
				end
			end
			if ctx.langs.ko then
				local K = get_ko()
				-- Korean segments: 2-4 letters (romanization or two-set keys)
				-- anywhere; a lone vowel letter is a complete syllable (아=a)
				-- and valid mid-pattern, same rule as Japanese vowels.
				for len = 4, 2, -1 do
					local seg = string.sub(str, 1, len)
					if #seg == len and K.pattern(seg) then
						local pk = copy(prefix)
						pk._alpha = false
						pk[#pk + 1] = { str = seg, type = "ko" }
						results = merge_table(results, parser(string.sub(str, len + 1), pk, ctx))
					end
				end
				if K.vowel_letter(firstchar) and K.pattern(firstchar) then
					local pk = copy(prefix)
					pk._alpha = false
					pk[#pk + 1] = { str = firstchar, type = "ko" }
					results = merge_table(results, parser(string.sub(str, 2), pk, ctx))
				end
			end
			if ctx.langs.en and (ctx.langs.alpha_mixing ~= false or prefix._alpha ~= false) then
				local p = copy(prefix)
				p[#p + 1] = { str = firstchar, type = "alpha" }
				results = merge_table(results, parser(string.sub(str, 2), p, ctx))
			end
			return results
		elseif ctx.langs.en and (ctx.langs.alpha_mixing ~= false or prefix._alpha ~= false)
			and vim.list_contains(chars, secondchar)
		then
			prefix[#prefix + 1] = { str = firstchar, type = "alpha" }
			prefix[#prefix + 1] = { str = secondchar, type = "comma" }
			return parser(string.sub(str, 3), prefix, ctx)
		elseif ctx.langs.en and (ctx.langs.alpha_mixing ~= false or prefix._alpha ~= false) then
			prefix[#prefix + 1] = { str = firstchar, type = "alpha" }
			prefix[#prefix + 1] = { str = secondchar, type = "other" }
			return parser(string.sub(str, 3), prefix, ctx)
		else
			return {}
		end
	elseif vim.list_contains(chars, firstchar) then
		prefix[#prefix + 1] = { str = firstchar, type = "comma" }
		return parser(string.sub(str, 2), prefix, ctx)
	else
		prefix[#prefix + 1] = { str = firstchar, type = "other" }
		return parser(string.sub(str, 2), prefix, ctx)
	end
end

-- ------------------------------------------------------------------
-- mid-input language forcing
-- A configurable key (default C-c / C-j / C-k / C-e) pressed inside the
-- flash prompt locks matching to one language. An internal marker
-- byte is kept in the pattern string itself: extending keeps the
-- lock, backspacing over it releases, and the last marker wins.
--
-- The pressed key and the marker byte are decoupled (see MARKER_BYTES):
-- C-j's newline never enters the pattern (flash's prompt buffer rejects
-- it), and C-c's getchar interrupt is intercepted by get_char_patch()
-- and dispatched to the lock action while a flash-cjk jump is active.

-- Internal marker bytes stored in the pattern. They are decoupled from
-- the pressed keys: C-j itself (\n) can never enter the pattern because
-- flash writes the pattern into its prompt buffer, which rejects
-- newlines. All marker bytes are buffer-safe control characters.
M.MARKER_BYTES = { cn = "\x01", jp = "\x02", ko = "\x04", en = "\x05" }

---Returns the marker table for the enabled force_keys.
---@param force_keys table lang -> key string (or false to disable)
---@return table markers { map = byte->lang, strip = pattern? }
local function markers_from_config(force_keys)
	local markers = { map = {}, strip = nil }
	local bytes = {}
	for lang, key in pairs(force_keys) do
		if type(key) == "string" and key ~= "" and M.MARKER_BYTES[lang] then
			markers.map[M.MARKER_BYTES[lang]] = lang
			bytes[#bytes + 1] = M.MARKER_BYTES[lang]
		end
	end
	if #bytes > 0 then
		markers.strip = "[" .. table.concat(bytes) .. "]"
	end
	return markers
end

---Splits a raw pattern into (clean_pattern, forced_lang?).
---The rightmost marker in the pattern wins.
---@param pattern string
---@param force_keys table? overrides the configured force_keys
---@return string clean
---@return string? forced "cn" | "jp" | "ko" | "en"
function M.parse_forced(pattern, force_keys)
	local markers = markers_from_config(force_keys or config.config.force_keys)
	if not markers.strip then
		return pattern, nil
	end
	local clean = string.gsub(pattern, markers.strip, "")
	local best_pos, best_lang = 0, nil
	for marker, lang in pairs(markers.map) do
		local pos = string.find(pattern, marker, 1, true)
		while pos do
			if pos > best_pos then
				best_pos, best_lang = pos, lang
			end
			pos = string.find(pattern, marker, pos + 1, true)
		end
	end
	return clean, best_lang
end

local function forced_langs(base, forced)
	return {
		cn = forced == "cn",
		jp = forced == "jp",
		ko = forced == "ko",
		en = forced == "en" or base.en,
		alpha_mixing = base.alpha_mixing,
	}
end

---@param langs table boolean language flags (see config.lang_flags)
---@param force_keys table? per-jump force_keys override
---@return fun(pattern: string): string, string
function M.make_mix_mode(langs, force_keys)
	local comma = comma_map(langs)
	local markers = force_keys ~= nil and markers_from_config(force_keys) or nil
	return function(str)
		local clean, forced
		if markers then
			clean, forced = M.parse_forced(str, force_keys)
		else
			clean, forced = M.parse_forced(str)
		end
		local eff_langs, eff_comma = langs, comma
		if forced then
			eff_langs = forced_langs(langs, forced)
			eff_comma = comma_map(eff_langs)
		end
		local all = parser(clean, nil, { count = 0, langs = eff_langs, comma = eff_comma })
		if #all == 0 then
			-- no interpretation at all (e.g. en disabled and the
			-- input has no pinyin/romaji reading): match the literal input
			local ret = "\\V" .. vim.fn.escape(clean, "\\")
			return ret, ret
		end
		local regexs = { [[\(]] }
		local seen = {}
		for _, v in ipairs(all) do
			local r = regex(v, eff_comma)
			if not seen[r] then
				seen[r] = true
				regexs[#regexs + 1] = r
				regexs[#regexs + 1] = [[\|]]
			end
		end
		regexs[#regexs] = [[\)]]
		local ret = table.concat(regexs)
		return ret, ret
	end
end

return M
