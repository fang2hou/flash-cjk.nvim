-- Language engine registry: the single access point to the per-language
-- matching engines. Every lang/<code>.lua module implements the same
-- surface, so consumers (match.lua's pattern compiler, labeler.lua's
-- predictions) never require an engine directly:
--   pattern(seg)        -> string?   vim regex fragment for one input
--                                segment, nil when nothing matches
--   strs(text, cap?)    -> string[]  every spelling the matched text
--                                could have been typed as (labeler)
--   comma               -> table?    punctuation key -> fragment;
--                                nil when the language has none
-- ko additionally exposes `vowel_letter` (its mid-pattern single-letter
-- rule); segment-length rules stay in the parser: they are language
-- knowledge, not interface.
--
-- en deliberately has no engine module: it is the literal fallback
-- domain (plain ASCII matches itself), carries no data and no
-- transformation -- a stub module would be pure ceremony and would skew
-- labeler predictions the moment it joined the strs loop.

local M = {}

local engines = {} ---@type table<string, table>

---Returns the engine for a language code, loading it on first use.
---@param code string "zhcn" | "ja" | "ko"
---@return table engine the pattern/strs/comma surface
function M.get(code)
	local e = engines[code]
	if e == nil then
		e = require("flash-cjk.lang." .. code)
		engines[code] = e
	end
	return e
end

return M
