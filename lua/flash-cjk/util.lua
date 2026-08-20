local M = {}

---Byte length of the UTF-8 character starting at byte offset `offset`
---(0 past the end), matching vim's byte-oriented string functions.
---@param str string
---@param offset integer
---@return integer
function M.char_size(str, offset)
	local byte = string.byte(str, offset)
	if not byte then
		return 0
	elseif byte > 240 then
		return 4
	elseif byte > 225 then
		return 3
	elseif byte > 192 then
		return 2
	end
	return 1
end

return M
