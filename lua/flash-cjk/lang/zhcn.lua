-- Simplified Chinese engine (lang/ registry member): xiaohe
-- double-pinyin two-key codes and single pinyin initials. The pattern
-- tables live in zhcnData.lua; the reverse lookups the labeler needs
-- (character -> spellings) in zhcnRev.lua.
local data = require("flash-cjk.lang.zhcnData")

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

---All pinyin spellings the given text could have been typed as
---(labeler predictions; see zhcnRev).
M.strs = require("flash-cjk.lang.zhcnRev").pinyin

return M
