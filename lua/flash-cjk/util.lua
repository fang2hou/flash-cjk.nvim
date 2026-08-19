-- Small helpers shared across modules. No plugin dependencies.

local M = {}

---Byte length of the UTF-8 character starting at byte offset `i`
---(0 past the end), matching vim's byte-oriented string functions.
---@param str string
---@param i integer
---@return integer
function M.char_size(str, i)
	local b = string.byte(str, i)
	if not b then
		return 0
	elseif b > 240 then
		return 4
	elseif b > 225 then
		return 3
	elseif b > 192 then
		return 2
	end
	return 1
end

return M
