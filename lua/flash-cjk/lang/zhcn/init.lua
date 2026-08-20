-- Simplified Chinese engine (lang/ registry member): xiaohe
-- double-pinyin two-key codes and single pinyin initials. The pattern
-- tables live in data.lua; below, the reverse lookups the labeler
-- needs (character -> spellings) are built from those same tables.
local data = require("flash-cjk.lang.zhcn.data")
local char_size = require("flash-cjk.util").char_size

local M = {}

M.comma = data.comma -- punctuation map (。 is shared with ja)

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

-- ------------------------------------------------------------------
-- labeler support: reverse lookups (character -> pinyin spellings)

local py_table = {}
local mt = {}
setmetatable(py_table, { __index = mt })

function py_table:insert(char, pinyin)
	if not self[char] then
		self[char] = {}
	end
	table.insert(self[char], pinyin)
end

function py_table:find(char)
	return self[char]
end

local function utf8_len(str)
	local len = 0
	local currentIndex = 1
	while currentIndex <= #str do
		currentIndex = currentIndex + char_size(str, currentIndex)
		len = len + 1
	end
	return len
end

local function utf8_sub(str, startChar, numChars)
	local startIndex = 1
	while startChar > 1 do
		startIndex = startIndex + char_size(str, startIndex)
		startChar = startChar - 1
	end

	local currentIndex = startIndex

	while numChars > 0 and currentIndex <= #str do
		currentIndex = currentIndex + char_size(str, currentIndex)
		numChars = numChars - 1
	end

	return string.sub(str, startIndex, currentIndex - 1)
end

local function init_py_table()
	-- both spellings a character is reachable through: the xiaohe
	-- initial (char1patterns, single-letter input) and the full
	-- syllable (char2patterns) -- mirroring the matcher's alternatives
	-- and the Rust CN_REVERSE table, so predictions and language
	-- attribution agree across paths
	for _, table_name in ipairs({ "char1patterns", "char2patterns" }) do
		for k, v in pairs(data[table_name]) do
			local start_char, end_char = v:find("%[(.-)%]")
			v = v:sub(start_char + 1, end_char - 1)
			for i = 1, utf8_len(v) do
				local char = utf8_sub(v, i, 1)
				py_table:insert(char, k)
			end
		end
	end
	for k, v in pairs(data.comma) do
		local start_char, end_char = v:find("%[(.-)%]")
		v = v:sub(start_char + 1, end_char - 1)
		for i = 1, utf8_len(v) do
			local char = utf8_sub(v, i, 1)
			py_table:insert(char, k)
		end
	end
end

local function append_to_pinyins(pinyins, suffixes)
	local result = {}
	if #pinyins == 0 then
		pinyins = { "" }
	end
	for i = 1, #pinyins do
		for j = 1, #suffixes do
			table.insert(result, pinyins[i] .. suffixes[j])
		end
	end
	return result
end

---All pinyin spellings the given text could have been typed as
---(labeler predictions). Characters without a known reading pass
---through as-is.
---@param text string
---@return string[]
function M.strs(text)
	local pinyins = {}
	for i = 1, utf8_len(text) do
		local char = utf8_sub(text, i, 1)
		if string.len(char) == 1 then
			pinyins = append_to_pinyins(pinyins, { char })
		else
			local char_pinyins = py_table:find(char)
			if not char_pinyins then
				pinyins = append_to_pinyins(pinyins, { char })
			else
				pinyins = append_to_pinyins(pinyins, char_pinyins)
			end
		end
	end
	return pinyins
end

init_py_table()

return M
