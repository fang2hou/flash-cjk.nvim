-- Matching domain: segmentation parser, punctuation classes, language
-- lock markers and the mixed-mode pattern compiler. Independent of
-- flash.nvim -- init.lua drives these through jump/remote/setup.

local config = require("flash-cjk.config")
local lang = require("flash-cjk.lang")

local M = {}

-- Engines resolve lazily through the lang registry: the first parse
-- pulls in exactly the enabled engines' data tables.
local ESCAPE = { ["\\"] = [[\\]] }

-- Upper bound on interpretations kept per keystroke; romaji segments
-- are 1-3 letters, so segmentation count grows quickly and longer
-- inputs degrade gracefully instead.
local MAX_SEGMENTATIONS = 600

local comma_cache = {} ---@type table<string, table<string,string>>
-- The cache key encodes the zhcn/ja flags -- the tables' only inputs
-- -- so entries self-invalidate when setup() changes the languages.

local function merge_class(a, b)
	if not a then
		return b
	end
	if not b then
		return a
	end
	return "[" .. string.sub(a, 2, -2) .. string.sub(b, 2, -2) .. "]"
end

-- Effective punctuation map: each enabled language contributes its own.
local function comma_map(langs)
	local cache_key = (langs.zhcn and "z" or "-") .. (langs.ja and "j" or "-")
	local map = comma_cache[cache_key]
	if not map then
		map = {}
		local cn_tbl = langs.zhcn and lang.get("zhcn").comma or {}
		local ja_tbl = langs.ja and lang.get("ja").comma or {}
		for _, src in ipairs({ cn_tbl, ja_tbl }) do
			for key, class in pairs(src) do
				map[key] = merge_class(map[key], class)
			end
		end
		comma_cache[cache_key] = map
	end
	return map
end

local function clone(tbl)
	local copy = {}
	for k, v in pairs(tbl) do
		copy[k] = v
	end
	return copy
end

local function append_all(dst, src)
	for i = 1, #src do
		table.insert(dst, src[i])
	end
	return dst
end

-- Copy a partial segmentation with one more segment appended.
local function extend(prefix, str, seg_type)
	local seg = clone(prefix)
	seg[#seg + 1] = { str = str, type = seg_type }
	return seg
end

local function make_nodes(comma)
	return {
		alpha = function(str)
			return "[" .. str .. string.upper(str) .. "]"
		end,
		pinyin = function(str)
			return lang.get("zhcn").pattern(str)
		end,
		comma = function(str)
			return comma[str]
		end,
		singlepin = function(str)
			return lang.get("zhcn").pattern(str)
		end,
		jp = function(str)
			return lang.get("ja").pattern(str)
		end,
		-- No data-table entry: the sokuon class is fixed by the rule.
		sokuon = function()
			return "[っッ]"
		end,
		ko = function(str)
			return lang.get("ko").pattern(str)
		end,
		other = function(str)
			return ESCAPE[str] or str
		end,
	}
end

local function regex(segments, comma)
	local nodes = make_nodes(comma)
	local fragments = {}
	for _, seg in ipairs(segments) do
		fragments[#fragments + 1] = nodes[seg.type](seg.str)
	end
	return table.concat(fragments)
end

-- Splits the input into every plausible sequence of segments.
-- A segment is one of: a literal letter (alpha), a 2-key xiaohe
-- double-pinyin code (pinyin), a single pinyin first letter
-- (singlepin), a 1-3 letter romaji prefix (jp), a geminate consonant
-- keystroke for っ/ッ (sokuon), a 1-4 letter Korean prefix (ko), a
-- punctuation key (comma) or any other character.
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
	local comma_keys = {}
	for key in pairs(ctx.comma) do
		table.insert(comma_keys, key)
	end
	-- Literal letters may follow a language segment only under
	-- mixed_input; prefix._alpha tracks whether the chain is still
	-- purely literal (nil = no language segment yet).
	local literal_ok = ctx.langs.en and (ctx.langs.mixed_input ~= false or prefix._alpha ~= false)
	if firstchar == "" then
		ctx.count = ctx.count + 1
		return { prefix }
	elseif string.match(firstchar, "%l") then
		local results = {}
		if secondchar == "" then
			if literal_ok then
				results = append_all(results, parser("", extend(prefix, firstchar, "alpha"), ctx))
			end
			if ctx.langs.zhcn then
				results =
					append_all(results, parser("", extend(prefix, firstchar, "singlepin"), ctx))
			end
			if ctx.langs.ja and lang.get("ja").pattern(firstchar) then
				results = append_all(results, parser("", extend(prefix, firstchar, "jp"), ctx))
			end
			if ctx.langs.ko and lang.get("ko").pattern(firstchar) then
				results = append_all(results, parser("", extend(prefix, firstchar, "ko"), ctx))
			end
			return results
		elseif string.match(secondchar, "%a") then
			-- longest / most specific segments first: when the
			-- segmentation budget runs out on long inputs, the
			-- informative branches (pinyin, romaji) survive instead of
			-- the literal alpha ones.
			if ctx.langs.zhcn and lang.get("zhcn").pattern(firstchar .. secondchar) then
				local seg = extend(prefix, firstchar .. secondchar, "pinyin")
				seg._alpha = false
				results = append_all(results, parser(string.sub(str, 3), seg, ctx))
			end
			if ctx.langs.ja then
				local ja_engine = lang.get("ja")
				local two = firstchar .. secondchar
				local three = two .. thirdchar
				if string.match(thirdchar, "%a") and ja_engine.pattern(three) then
					local seg = extend(prefix, three, "jp")
					seg._alpha = false
					results = append_all(results, parser(string.sub(str, 4), seg, ctx))
				end
				if ja_engine.pattern(two) then
					local seg = extend(prefix, two, "jp")
					seg._alpha = false
					results = append_all(results, parser(string.sub(str, 3), seg, ctx))
				end
				-- Geminate consonant: a doubled consonant key (kk, ss, tt, ...)
				-- or the "t" of "tch" is a keystroke of its own for っ/ッ, so it
				-- segments as a single letter mid-pattern. Tried before the
				-- vowel/n singles: the triggers are disjoint, and the Rust
				-- parser mirrors this exact alternation order.
				local doubled = secondchar == firstchar
					and not vim.list_contains({ "a", "e", "i", "o", "u", "n" }, firstchar)
				local tch = firstchar == "t" and secondchar == "c" and thirdchar == "h"
				if doubled or tch then
					local seg = extend(prefix, firstchar, "sokuon")
					seg._alpha = false
					results = append_all(results, parser(string.sub(str, 2), seg, ctx))
				end
				-- Mid-pattern single-letter romaji is only kept for keys
				-- that are complete syllables on their own (vowels + n);
				-- consonant prefixes are always typed to completion, so
				-- they only matter as the last, unfinished segment.
				if
					vim.list_contains({ "a", "e", "i", "o", "u", "n" }, firstchar)
					and ja_engine.pattern(firstchar)
				then
					local seg = extend(prefix, firstchar, "jp")
					seg._alpha = false
					results = append_all(results, parser(string.sub(str, 2), seg, ctx))
				end
			end
			if ctx.langs.ko then
				local ko_engine = lang.get("ko")
				-- 2-4 letter segments (romanization or two-set keys)
				-- anywhere; a lone vowel letter is a complete syllable
				-- (아=a) and valid mid-pattern, same rule as Japanese
				-- vowels.
				for seg_len = 4, 2, -1 do
					local seg_str = string.sub(str, 1, seg_len)
					if #seg_str == seg_len and ko_engine.pattern(seg_str) then
						local seg = extend(prefix, seg_str, "ko")
						seg._alpha = false
						results =
							append_all(results, parser(string.sub(str, seg_len + 1), seg, ctx))
					end
				end
				if ko_engine.vowel_letter(firstchar) and ko_engine.pattern(firstchar) then
					local seg = extend(prefix, firstchar, "ko")
					seg._alpha = false
					results = append_all(results, parser(string.sub(str, 2), seg, ctx))
				end
			end
			if literal_ok then
				results = append_all(
					results,
					parser(string.sub(str, 2), extend(prefix, firstchar, "alpha"), ctx)
				)
			end
			return results
		elseif literal_ok and vim.list_contains(comma_keys, secondchar) then
			prefix[#prefix + 1] = { str = firstchar, type = "alpha" }
			prefix[#prefix + 1] = { str = secondchar, type = "comma" }
			return parser(string.sub(str, 3), prefix, ctx)
		elseif literal_ok then
			prefix[#prefix + 1] = { str = firstchar, type = "alpha" }
			prefix[#prefix + 1] = { str = secondchar, type = "other" }
			return parser(string.sub(str, 3), prefix, ctx)
		else
			return {}
		end
	elseif vim.list_contains(comma_keys, firstchar) then
		prefix[#prefix + 1] = { str = firstchar, type = "comma" }
		return parser(string.sub(str, 2), prefix, ctx)
	else
		prefix[#prefix + 1] = { str = firstchar, type = "other" }
		return parser(string.sub(str, 2), prefix, ctx)
	end
end

-- A configurable key (default C-c / C-j / C-k / C-e) pressed inside
-- the flash prompt locks matching to one language. An internal marker
-- byte is stored in the pattern string itself: extending keeps the
-- lock, backspacing over it releases it, and the last marker wins.
-- The key and the marker byte are decoupled because C-j's newline can
-- never enter the pattern (flash's prompt buffer rejects newlines).
M.MARKER_BYTES = { zhcn = "\x01", ja = "\x02", ko = "\x04", en = "\x05" }

---Returns the marker table for the enabled filter_keys.
---@param filter_keys table lang -> key string (or false to disable)
---@return table markers { map = byte->lang, strip = pattern? }
local function markers_from_config(filter_keys)
	local markers = { map = {}, strip = nil }
	local bytes = {}
	for code, key in pairs(filter_keys) do
		if type(key) == "string" and key ~= "" and M.MARKER_BYTES[code] then
			markers.map[M.MARKER_BYTES[code]] = code
			bytes[#bytes + 1] = M.MARKER_BYTES[code]
		end
	end
	if #bytes > 0 then
		markers.strip = "[" .. table.concat(bytes) .. "]"
	end
	return markers
end

---Splits a raw pattern into (clean_pattern, locked_lang?).
---The rightmost marker in the pattern wins.
---@param pattern string
---@param filter_keys table? overrides the configured filter_keys
---@return string clean
---@return string? locked "zhcn" | "ja" | "ko" | "en"
function M.parse_filter(pattern, filter_keys)
	local markers = markers_from_config(filter_keys or config.filter_keys(config.config.languages))
	if not markers.strip then
		return pattern, nil
	end
	local clean = string.gsub(pattern, markers.strip, "")
	local best_pos, best_lang = 0, nil
	for marker, code in pairs(markers.map) do
		local pos = string.find(pattern, marker, 1, true)
		while pos do
			if pos > best_pos then
				best_pos, best_lang = pos, code
			end
			pos = string.find(pattern, marker, pos + 1, true)
		end
	end
	return clean, best_lang
end

local function locked_langs(base, locked)
	return {
		zhcn = locked == "zhcn",
		ja = locked == "ja",
		ko = locked == "ko",
		en = locked == "en" or base.en,
		mixed_input = base.mixed_input,
	}
end

---@param langs table boolean language flags (see config.lang_flags)
---@param filter_keys table? per-jump filter_keys override
---@return fun(pattern: string): string, string
function M.make_mix_mode(langs, filter_keys)
	local comma = comma_map(langs)
	local markers = filter_keys ~= nil and markers_from_config(filter_keys) or nil
	return function(str)
		local clean, locked
		if markers then
			clean, locked = M.parse_filter(str, filter_keys)
		else
			clean, locked = M.parse_filter(str)
		end
		local eff_langs, eff_comma = langs, comma
		if locked then
			eff_langs = locked_langs(langs, locked)
			eff_comma = comma_map(eff_langs)
		end
		local all = parser(clean, nil, { count = 0, langs = eff_langs, comma = eff_comma })
		if #all == 0 then
			-- no interpretation at all (e.g. en disabled and no reading
			-- matches): match the literal input
			local ret = "\\V" .. vim.fn.escape(clean, "\\")
			return ret, ret
		end
		local alternatives = { [[\(]] }
		local seen = {}
		for _, seg in ipairs(all) do
			local r = regex(seg, eff_comma)
			if not seen[r] then
				seen[r] = true
				alternatives[#alternatives + 1] = r
				alternatives[#alternatives + 1] = [[\|]]
			end
		end
		alternatives[#alternatives] = [[\)]]
		-- Youon data fragments carry capturing groups; with many
		-- alternatives the pattern would cross vim's 9-group cap (E872).
		-- The pattern is search-only, so none of them need to capture.
		local ret = string.gsub(table.concat(alternatives), "%\\%(", "\\%%(")
		return ret, ret
	end
end

return M
