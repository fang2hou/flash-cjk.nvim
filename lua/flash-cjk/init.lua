local flypy = require("flash-cjk.flypy")

local M = {}

-- Default configuration: every matcher is enabled. Each flag can be
-- turned off globally via setup(), or per jump via jump({ langs = ... }):
--   cn       pinyin matching (flypy + first letter)
--   jp       romaji matching (kanji readings + kana)
--   original literal ASCII letters, i.e. plain flash.nvim behavior
M.config = {
	langs = {
		cn = true,
		jp = true,
		original = true,
	},
}

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

local function resolve_langs(opts)
	return vim.tbl_deep_extend("force", {}, M.config.langs, opts.langs or {})
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
	ctx = ctx or {
		count = 0,
		langs = M.config.langs,
		comma = comma_map(M.config.langs),
	}
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
			if ctx.langs.original then
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
			return results
		elseif string.match(secondchar, "%a") then
			-- longest / most specific segments first: when the segmentation
			-- budget runs out on long inputs, the informative branches
			-- (pinyin, romaji) survive instead of the literal alpha ones
			if ctx.langs.cn and flypy.char2patterns[firstchar .. secondchar] then
				local p = M.copy(prefix)
				p[#p + 1] = { str = firstchar .. secondchar, type = "pinyin" }
				results = M.merge_table(results, M.parser(string.sub(str, 3), p, ctx))
			end
			if ctx.langs.jp then
				local J = get_jp()
				local two = firstchar .. secondchar
				local three = two .. thirdchar
				if string.match(thirdchar, "%a") and J.pattern(three) then
					local pj = M.copy(prefix)
					pj[#pj + 1] = { str = three, type = "jp" }
					results = M.merge_table(results, M.parser(string.sub(str, 4), pj, ctx))
				end
				if J.pattern(two) then
					local pj = M.copy(prefix)
					pj[#pj + 1] = { str = two, type = "jp" }
					results = M.merge_table(results, M.parser(string.sub(str, 3), pj, ctx))
				end
				if J.pattern(firstchar) then
					local pj = M.copy(prefix)
					pj[#pj + 1] = { str = firstchar, type = "jp" }
					results = M.merge_table(results, M.parser(string.sub(str, 2), pj, ctx))
				end
			end
			if ctx.langs.original then
				local p = M.copy(prefix)
				p[#p + 1] = { str = firstchar, type = "alpha" }
				results = M.merge_table(results, M.parser(string.sub(str, 2), p, ctx))
			end
			return results
		elseif ctx.langs.original and vim.list_contains(chars, secondchar) then
			prefix[#prefix + 1] = { str = firstchar, type = "alpha" }
			prefix[#prefix + 1] = { str = secondchar, type = "comma" }
			return M.parser(string.sub(str, 3), prefix, ctx)
		elseif ctx.langs.original then
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

---Builds a flash search mode function for the given language flags.
---@param langs table<string, boolean>
---@return fun(str: string): string, string
function M.make_mix_mode(langs)
	local comma = comma_map(langs)
	return function(str)
		local all = M.parser(str, nil, { count = 0, langs = langs, comma = comma })
		if #all == 0 then
			-- no interpretation at all (e.g. original disabled and the
			-- input has no pinyin/romaji reading): match the literal input
			local ret = "\\V" .. vim.fn.escape(str, "\\")
			return ret, ret
		end
		local regexs = { [[\(]] }
		local seen = {}
		for _, v in ipairs(all) do
			local r = M.regex(v, comma)
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

-- Default mixed mode: every enabled language.
M.mix_mode = M.make_mix_mode(M.config.langs)

-- ------------------------------------------------------------------
-- public API

local function build_opts(opts)
	local langs = resolve_langs(opts)
	local mode = M.make_mix_mode(langs)
	return vim.tbl_deep_extend("force", {
		labels = "asdfghjklqwertyuiopzxcvbnm",
		search = {
			mode = mode,
		},
		labeler = function(_, state)
			require("flash-cjk.labeler").new(state, langs):update()
		end,
	}, opts)
end

function M.jump(opts)
	opts = opts or {}
	get_flash().jump(build_opts(opts))
end

function M.remote(opts)
	opts = opts or {}
	get_flash().remote(build_opts(opts))
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
-- @field opts.langs table Language switches: { cn = boolean, jp = boolean, original = boolean }.
-- @field opts.char_map table Char map for flypy.
-- @field[opt] opts.char_map.comma table Override the default comma map.
-- @field[opt] opts.char_map.append_comma table Append to the default comma map.
-- @field[opt] opts.char_map.append_char1 table Append to the default char1patterns map.
-- @field[opt] opts.char_map.append_char2 table Append to the default char2patterns map.
function M.setup(opts)
	opts = opts or {}
	if opts.langs then
		for _, l in ipairs({ "cn", "jp", "original" }) do
			if type(opts.langs[l]) == "boolean" then
				M.config.langs[l] = opts.langs[l]
			end
		end
		comma_cache = {}
		M.mix_mode = M.make_mix_mode(M.config.langs)
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
