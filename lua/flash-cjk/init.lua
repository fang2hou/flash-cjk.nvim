local flypy = require("flash-cjk.flypy")

local M = {}

-- Default configuration: every language is enabled. Each entry can be
-- tuned via setup():
--   cn/jp/ko      true (default scheme), false, or a scheme name
--                 (see SCHEMES below: cn "xiaohe", jp/ko "roma")
--   en            literal ASCII letters, i.e. plain flash.nvim behavior
--   alpha_mixing  false additionally drops interpretations that mix
--                 literal letters with language segments (e.g. alpha
--                 "n" + pinyin "i"); the original flash-zh behavior
--                 keeps them; turning mixing off trades some
--                 mixed-chain reachability (e.g. pinyin "nihao"
--                 variants) for lower regex cost on long inputs;
--                 measure before enabling.
-- Per-jump overrides take an array of language codes instead, e.g.
-- jump({ "cn", "en" }) -- see M.resolve_langs.
M.config = {
	cn = "xiaohe",
	jp = "roma",
	ko = "roma",
	en = true,
	alpha_mixing = true,
	-- Keys that lock matching to a single language mid-input. The raw
	-- key bytes are never stored in the pattern; each lock writes a
	-- buffer-safe internal marker instead (C-j's newline would break
	-- flash's prompt). C-c's interrupt is intercepted and dispatched to
	-- the lock action while a flash-cjk jump is active.
	force_keys = {
		cn = "<C-c>",
		jp = "<C-j>",
		ko = "<C-k>",
		en = "<C-e>",
	},
}

-- Registered matching schemes per language. Each language currently
-- ships exactly one scheme: the string validates and records the
-- choice without changing matching behavior (future schemes plug in
-- here).
local SCHEMES = {
	cn = { default = "xiaohe", xiaohe = true },
	jp = { default = "roma", roma = true },
	ko = { default = "roma", roma = true },
}

-- Normalizes a setup value for cn/jp/ko: true -> the default scheme
-- name, a string -> the validated scheme, false -> false.
local function normalize_lang(lang, value)
	if value == true then
		return SCHEMES[lang].default
	elseif type(value) == "string" then
		if SCHEMES[lang][value] then
			return value
		end
		error(("flash-cjk: unknown %s scheme %q"):format(lang, value))
	elseif value == false then
		return false
	end
	error(("flash-cjk: %s must be a boolean or scheme string"):format(lang))
end

-- Boolean language flags derived from config, as consumed by the
-- parser, labeler and the Rust bridge (cn/jp/ko are enabled unless
-- the scheme is explicitly false).
local function lang_flags()
	return {
		cn = M.config.cn ~= false,
		jp = M.config.jp ~= false,
		ko = M.config.ko ~= false,
		en = M.config.en,
		alpha_mixing = M.config.alpha_mixing,
	}
end

-- Upper bound on the number of pattern interpretations kept per keystroke.
-- Romaji segments are 1-3 letters long, so the number of possible
-- segmentations grows quickly; longer inputs degrade gracefully instead.
local MAX_SEGMENTATIONS = 600

-- flash.nvim is only needed when actually jumping, and jp data (1 MB) is
-- only worth loading when Japanese matching is enabled.
local function get_flash()
	return require("flash")
end

local jp ---@type table?
local function get_jp()
	if jp == nil then
		jp = require("flash-cjk.jp")
	end
	return jp
end

local ko ---@type table?
local function get_ko()
	if ko == nil then
		ko = require("flash-cjk.ko")
	end
	return ko
end

---Resolves a jump/remote language array into boolean language flags.
---nil or {} -> the setup-enabled set; otherwise the array fully
---decides the enabled set for this jump ("kr" is an alias of "ko";
---alpha_mixing always comes from config).
---@param ary string[]? language codes, e.g. { "cn", "en" }
---@return table langs boolean flags
function M.resolve_langs(ary)
	if ary == nil or #ary == 0 then
		return lang_flags()
	end
	local langs = { cn = false, jp = false, ko = false, en = false, alpha_mixing = M.config.alpha_mixing }
	for _, code in ipairs(ary) do
		local lang = code == "kr" and "ko" or code
		if lang ~= "cn" and lang ~= "jp" and lang ~= "ko" and lang ~= "en" then
			error("flash-cjk: unknown language code: " .. tostring(code))
		end
		langs[lang] = true
	end
	return langs
end

-- ------------------------------------------------------------------
-- punctuation

local comma_cache = {} ---@type table<string, table<string,string>>

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
		local cn_tbl = langs.cn and flypy.comma or {}
		local jp_tbl = langs.jp and get_jp().comma or {}
		for _, src in ipairs({ cn_tbl, jp_tbl }) do
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


local function make_nodes(comma)
	return {
		alpha = function(str)
			return "[" .. str .. string.upper(str) .. "]"
		end,
		pinyin = function(str)
			return flypy.char2patterns[str]
		end,
		comma = function(str)
			return comma[str]
		end,
		singlepin = function(str)
			return flypy.char1patterns[str]
		end,
		jp = function(str)
			return get_jp().pattern(str)
		end,
		ko = function(str)
			return get_ko().pattern(str)
		end,
		other = function(str)
			str = flypy.escape[str] or str
			return str
		end,
	}
end

function M.regex(parser, comma)
	local nodes = make_nodes(comma or comma_map({ cn = true, jp = false }))
	local regexs = {}
	for _, v in ipairs(parser) do
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
function M.parser(str, prefix, ctx)
	prefix = prefix or {}
	if ctx == nil then
		local flags = lang_flags()
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
				local p1 = M.copy(prefix)
				p1[#p1 + 1] = { str = firstchar, type = "alpha" }
				results = M.merge_table(results, M.parser("", p1, ctx))
			end
			if ctx.langs.cn then
				local p2 = M.copy(prefix)
				p2[#p2 + 1] = { str = firstchar, type = "singlepin" }
				results = M.merge_table(results, M.parser("", p2, ctx))
			end
			if ctx.langs.jp and get_jp().pattern(firstchar) then
				local p3 = M.copy(prefix)
				p3[#p3 + 1] = { str = firstchar, type = "jp" }
				results = M.merge_table(results, M.parser("", p3, ctx))
			end
			if ctx.langs.ko and get_ko().pattern(firstchar) then
				local p4 = M.copy(prefix)
				p4[#p4 + 1] = { str = firstchar, type = "ko" }
				results = M.merge_table(results, M.parser("", p4, ctx))
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
			if ctx.langs.cn and flypy.char2patterns[firstchar .. secondchar] then
				local p = M.copy(prefix)
				p._alpha = false
				p[#p + 1] = { str = firstchar .. secondchar, type = "pinyin" }
				results = M.merge_table(results, M.parser(string.sub(str, 3), p, ctx))
			end
			if ctx.langs.jp then
				local J = get_jp()
				local two = firstchar .. secondchar
				local three = two .. thirdchar
				if string.match(thirdchar, "%a") and J.pattern(three) then
					local pj = M.copy(prefix)
					pj._alpha = false
					pj[#pj + 1] = { str = three, type = "jp" }
					results = M.merge_table(results, M.parser(string.sub(str, 4), pj, ctx))
				end
				if J.pattern(two) then
					local pj = M.copy(prefix)
					pj._alpha = false
					pj[#pj + 1] = { str = two, type = "jp" }
					results = M.merge_table(results, M.parser(string.sub(str, 3), pj, ctx))
				end
				-- Mid-pattern single-letter romaji is only kept for keys that
				-- are complete syllables on their own (vowels + n: あおい, にほんご);
				-- consonant prefixes (ka, tsu...) are always typed to completion,
				-- so they only matter as the last, unfinished segment.
				if vim.list_contains({ "a", "e", "i", "o", "u", "n" }, firstchar) and J.pattern(firstchar) then
					local pj = M.copy(prefix)
					pj._alpha = false
					pj[#pj + 1] = { str = firstchar, type = "jp" }
					results = M.merge_table(results, M.parser(string.sub(str, 2), pj, ctx))
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
						local pk = M.copy(prefix)
						pk._alpha = false
						pk[#pk + 1] = { str = seg, type = "ko" }
						results = M.merge_table(results, M.parser(string.sub(str, len + 1), pk, ctx))
					end
				end
				if K.vowel_letter(firstchar) and K.pattern(firstchar) then
					local pk = M.copy(prefix)
					pk._alpha = false
					pk[#pk + 1] = { str = firstchar, type = "ko" }
					results = M.merge_table(results, M.parser(string.sub(str, 2), pk, ctx))
				end
			end
			if ctx.langs.en and (ctx.langs.alpha_mixing ~= false or prefix._alpha ~= false) then
				local p = M.copy(prefix)
				p[#p + 1] = { str = firstchar, type = "alpha" }
				results = M.merge_table(results, M.parser(string.sub(str, 2), p, ctx))
			end
			return results
		elseif ctx.langs.en and (ctx.langs.alpha_mixing ~= false or prefix._alpha ~= false)
			and vim.list_contains(chars, secondchar)
		then
			prefix[#prefix + 1] = { str = firstchar, type = "alpha" }
			prefix[#prefix + 1] = { str = secondchar, type = "comma" }
			return M.parser(string.sub(str, 3), prefix, ctx)
		elseif ctx.langs.en and (ctx.langs.alpha_mixing ~= false or prefix._alpha ~= false) then
			prefix[#prefix + 1] = { str = firstchar, type = "alpha" }
			prefix[#prefix + 1] = { str = secondchar, type = "other" }
			return M.parser(string.sub(str, 3), prefix, ctx)
		else
			return {}
		end
	elseif vim.list_contains(chars, firstchar) then
		prefix[#prefix + 1] = { str = firstchar, type = "comma" }
		return M.parser(string.sub(str, 2), prefix, ctx)
	else
		prefix[#prefix + 1] = { str = firstchar, type = "other" }
		return M.parser(string.sub(str, 2), prefix, ctx)
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
local MARKER_BYTES = { cn = "\x01", jp = "\x02", ko = "\x04", en = "\x05" }

---Returns the marker table for the enabled force_keys.
---@param force_keys table lang -> key string (or false to disable)
---@return table markers { map = byte->lang, strip = pattern? }
local function markers_from_config(force_keys)
	local markers = { map = {}, strip = nil }
	local bytes = {}
	for lang, key in pairs(force_keys) do
		if type(key) == "string" and key ~= "" and MARKER_BYTES[lang] then
			markers.map[MARKER_BYTES[lang]] = lang
			bytes[#bytes + 1] = MARKER_BYTES[lang]
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
---@param force_keys table? overrides M.config.force_keys
---@return string clean
---@return string? forced "cn" | "jp" | "ko" | "en"
function M.parse_forced(pattern, force_keys)
	local markers = markers_from_config(force_keys or M.config.force_keys)
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
		local all = M.parser(clean, nil, { count = 0, langs = eff_langs, comma = eff_comma })
		if #all == 0 then
			-- no interpretation at all (e.g. en disabled and the
			-- input has no pinyin/romaji reading): match the literal input
			local ret = "\\V" .. vim.fn.escape(clean, "\\")
			return ret, ret
		end
		local regexs = { [[\(]] }
		local seen = {}
		for _, v in ipairs(all) do
			local r = M.regex(v, eff_comma)
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

-- Default mixed mode: every enabled language, default force keys.
M.mix_mode = M.make_mix_mode(lang_flags(), M.config.force_keys)

-- ------------------------------------------------------------------
-- Swallows the C-c interrupt inside flash's input loop when (and only
-- when) the currently active flash state has a C-c language-lock action
-- registered (i.e. a flash-cjk jump with C-c bound). Plain flash jumps
-- keep their original behavior: the interrupt returns nil and exits.
local function get_char_patch()
	local ok, Util = pcall(require, "flash.util")
	if not ok or type(Util.get_char) ~= "function" or Util._flash_cjk_patched then
		return
	end
	Util._flash_cjk_patched = true
	Util.get_char = function()
		local Hacks = require("flash.hacks")
		Hacks.setcursor()
		vim.cmd("redraw")
		local ok2, ret = pcall(vim.fn.getcharstr)
		if not ok2 then
			local okS, State = pcall(require, "flash.state")
			if okS then
				for state in pairs(State._states or {}) do
					-- only visible (actively looping) states: stale states
					-- kept alive by repeat references must not swallow C-c
					if state.visible
						and state.opts
						and state.opts.actions
						and state.opts.actions["\x03"]
					then
						return "\x03"
					end
				end
			end
			return nil
		end
		return ret ~= Util.t("<esc>") and ret or nil
	end
end

-- Makes the lock state visible in flash's prompt: marker bytes would
-- render as raw control characters (^A, ^B...); they are shown as
-- readable [中]/[日]/[韩]/[英] tags instead. Only the display string
-- is transformed -- the real pattern keeps its marker bytes.
local function prompt_patch()
	local ok, Prompt = pcall(require, "flash.prompt")
	if not ok or type(Prompt.set) ~= "function" or Prompt._flash_cjk_patched then
		return
	end
	Prompt._flash_cjk_patched = true
	local orig = Prompt.set
	Prompt.set = function(pattern, show)
		local display = pattern
			:gsub("\x01", " [中]")
			:gsub("\x02", " [日]")
			:gsub("\x04", " [韩]")
			:gsub("\x05", " [英]")
		return orig(display, show)
	end
end

local function build_opts(langs, opts)
	local keys = vim.tbl_deep_extend("force", {}, M.config.force_keys, opts.force_keys or {})
	local mode = M.make_mix_mode(langs, keys)
	local actions = {}
	for _, lang in ipairs({ "cn", "jp", "ko", "en" }) do
		local key = keys[lang]
		if type(key) == "string" and key ~= "" then
			local marker = MARKER_BYTES[lang]
			actions[vim.api.nvim_replace_termcodes(key, true, true, true)] = function(state, _)
				state:update({ pattern = state.pattern:extend(marker) })
				return true
			end
		end
	end
	-- C-c never reaches flash's actions: getcharstr raises an interrupt
	-- for it. Patch Util.get_char so that the interrupt is swallowed and
	-- the raw byte is returned for action dispatch -- but only while a
	-- C-c language lock is actually configured; everything else keeps
	-- flash's original behavior.
	get_char_patch()
	prompt_patch()
	-- Rust fast path: when the binary exists it replaces the vim-regex
	-- searcher entirely; per-keystroke failures fall back to the default
	-- searcher inside the bridge (see lua/flash-cjk/rust.lua)
	local defaults = {
		labels = "asdfghjklqwertyuiopzxcvbnm",
		search = {
			mode = mode,
		},
		actions = actions,
		labeler = function(_, state)
			require("flash-cjk.labeler").new(state, langs, keys):update()
		end,
	}
	local rust_ok, rust = pcall(require, "flash-cjk.rust")
	if rust_ok and rust.available() then
		defaults.matcher = rust.matcher(langs)
	end
	return vim.tbl_deep_extend("force", defaults, opts)
end

function M.jump(langs, opts)
	get_flash().jump(build_opts(M.resolve_langs(langs), opts or {}))
end

function M.remote(langs, opts)
	get_flash().remote(build_opts(M.resolve_langs(langs), opts or {}))
end

function M.merge_table(tab1, tab2)
	for i = 1, #tab2 do
		table.insert(tab1, tab2[i])
	end
	return tab1
end

function M.copy(table)
	local copy = {}
	for k, v in pairs(table) do
		copy[k] = v
	end
	return copy
end

-- @param opts table
-- @field[opt] opts.cn boolean|string Chinese matching: true (default scheme "xiaohe"), false, or a scheme name.
-- @field[opt] opts.jp boolean|string Japanese matching: true (default scheme "roma"), false, or a scheme name.
-- @field[opt] opts.ko boolean|string Korean matching: true (default scheme "roma"), false, or a scheme name.
-- @field[opt] opts.en boolean Literal ASCII letter matching.
-- @field[opt] opts.alpha_mixing boolean Allow mixing literal letters into language chains.
-- @field opts.force_keys table Language-lock keys, e.g. { cn = "<C-c>" }; false disables one.
-- @field opts.char_map table Char map for flypy.
-- @field[opt] opts.char_map.comma table Override the default comma map.
-- @field[opt] opts.char_map.append_comma table Append to the default comma map.
-- @field[opt] opts.char_map.append_char1 table Append to the default char1patterns map.
-- @field[opt] opts.char_map.append_char2 table Append to the default char2patterns map.
function M.setup(opts)
	opts = opts or {}
	local dirty = false
	for _, lang in ipairs({ "cn", "jp", "ko" }) do
		if opts[lang] ~= nil then
			M.config[lang] = normalize_lang(lang, opts[lang])
			dirty = true
		end
	end
	for _, key in ipairs({ "en", "alpha_mixing" }) do
		if type(opts[key]) == "boolean" then
			M.config[key] = opts[key]
			dirty = true
		end
	end
	if dirty then
		comma_cache = {}
		M.mix_mode = M.make_mix_mode(lang_flags())
	end
	if opts.force_keys then
		for lang, key in pairs(opts.force_keys) do
			if vim.list_contains({ "cn", "jp", "ko", "en" }, lang) then
				M.config.force_keys[lang] = key -- string key, or false to disable
			end
		end
	end
	if not opts.char_map then
		return
	end
	local to_escape = "\\^$*+?.%|[]()"
	if opts.char_map.comma then
		for k, v in pairs(opts.char_map.comma) do
			if #k ~= 1 then
				error("comma key must be a single character")
			else
				v = vim.fn.escape(v, to_escape)
				flypy.comma[k] = "[" .. v .. "]"
			end
		end
	end
	if opts.char_map.append_comma then
		for k, v in pairs(opts.char_map.append_comma) do
			if #k ~= 1 then
				error("append_comma key must be a single character")
			else
				local chars = flypy.comma[k] or ""
				chars = string.sub(chars, 2, -2) .. vim.fn.escape(v, to_escape)
				flypy.comma[k] = "[" .. chars .. "]"
			end
		end
	end
	if opts.char_map.append_char1 then
		for k, v in pairs(opts.char_map.append_char1) do
			if #k ~= 1 then
				error("append_char1 key must be a single character")
			else
				local chars = flypy.char1patterns[k] or ""
				chars = string.sub(chars, 2, -2) .. vim.fn.escape(v, to_escape)
				flypy.char1patterns[k] = "[" .. chars .. "]"
			end
		end
	end
	if opts.char_map.append_char2 then
		for k, v in pairs(opts.char_map.append_char2) do
			if #k ~= 2 then
				error("append_char2 key must be two characters")
			else
				local chars = flypy.char2patterns[k] or ""
				chars = string.sub(chars, 2, -2) .. vim.fn.escape(v, to_escape)
				flypy.char2patterns[k] = "[" .. chars .. "]"
			end
		end
	end
	-- char_map edits flypy.comma in place: drop cached merged maps
	comma_cache = {}
end

return M
