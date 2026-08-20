-- Simplified Chinese engine: xiaohe double-pinyin two-key codes and
-- single pinyin initials (pattern tables in data.json). The labeler's
-- reverse lookup (character -> spellings) is built here from the same
-- tables, mirroring the matcher's alternatives and Rust's CN_REVERSE so
-- predictions agree across both paths.

local data = require("flash-cjk.lang").data("zhcn")
local char_size = require("flash-cjk.util").char_size

local M = {}

M.comma = data.comma

---Regex fragment for a 1-2 letter input segment: a two-key xiaohe
---code, or a single pinyin initial letter. nil when nothing matches.
---@param seg string
---@return string?
function M.pattern(seg)
	if #seg == 1 then
		return data.char1patterns[seg]
	end
	return data.char2patterns[seg]
end

local spellings = {} ---@type table<string, string[]>

local function add_spelling(char, spelling)
	local list = spellings[char]
	if not list then
		list = {}
		spellings[char] = list
	end
	list[#list + 1] = spelling
end

local function utf8_len(str)
	local len = 0
	local pos = 1
	while pos <= #str do
		pos = pos + char_size(str, pos)
		len = len + 1
	end
	return len
end

local function utf8_char_at(str, index)
	local start = 1
	for _ = 1, index - 1 do
		start = start + char_size(str, start)
	end
	return string.sub(str, start, start + char_size(str, start) - 1)
end

local function class_chars(class)
	local start_char, end_char = class:find("%[(.-)%]")
	return class:sub(start_char + 1, end_char - 1)
end

for _, table_name in ipairs({ "char1patterns", "char2patterns", "comma" }) do
	for key, class in pairs(data[table_name]) do
		local chars = class_chars(class)
		for i = 1, utf8_len(chars) do
			add_spelling(utf8_char_at(chars, i), key)
		end
	end
end

local function combine(prefixes, suffixes)
	if #prefixes == 0 then
		prefixes = { "" }
	end
	local out = {}
	for _, prefix in ipairs(prefixes) do
		for _, suffix in ipairs(suffixes) do
			out[#out + 1] = prefix .. suffix
		end
	end
	return out
end

---All pinyin spellings the given text could have been typed as (labeler
---predictions). Characters without a known reading pass through as-is.
---@param text string
---@return string[]
function M.strs(text)
	local pinyins = {}
	for i = 1, utf8_len(text) do
		local char = utf8_char_at(text, i)
		local char_pinyins = spellings[char]
		if char_pinyins == nil or string.len(char) == 1 then
			char_pinyins = { char }
		end
		pinyins = combine(pinyins, char_pinyins)
	end
	return pinyins
end

return M
