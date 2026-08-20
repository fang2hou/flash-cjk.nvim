-- Language engine registry. Each language owns lang/<code>/: init.lua is
-- the engine, data.json its dictionary. Every engine implements the same
-- surface so consumers never require one directly:
--   pattern(seg)     -> string?  vim regex fragment for one input segment
--   strs(text, cap?) -> string[] spellings the matched text could be typed as
--   comma            -> table?   punctuation key -> fragment
-- en has no engine: it is the literal fallback domain, and a stub module
-- would only pollute the labeler's spelling loop.

local M = {}

local engines = {} ---@type table<string, table>
local datasets = {} ---@type table<string, table>

---Returns the engine for a language code, loading it on first use.
---@param code string "zhcn" | "ja" | "ko"
---@return table engine the pattern/strs/comma surface
function M.get(code)
	local engine = engines[code]
	if engine == nil then
		engine = require("flash-cjk.lang." .. code)
		engines[code] = engine
	end
	return engine
end

---Loads lang/<code>/data.json, decoding it once per session. `luanil`
---turns JSON null back into real nil so holey arrays survive the round
---trip (ko's shift-only key tables depend on it).
---@param code string
---@return table data
function M.data(code)
	local data = datasets[code]
	if data == nil then
		local dir = vim.fs.dirname(debug.getinfo(1, "S").source:sub(2))
		local file = assert(io.open(("%s/%s/data.json"):format(dir, code))) ---@type file*
		local raw = file:read("*a")
		file:close()
		data = vim.json.decode(raw, { luanil = { object = true, array = true } })
		datasets[code] = data
	end
	return data
end

return M
