-- Configuration state: defaults and language-flag resolution. No
-- flash.nvim dependency -- setup() writes into M.config and the mix
-- mode is rebuilt from it on change. Field semantics are documented
-- in the README.

local M = {}

local LANGS = { "zhcn", "ja", "ko", "en" }

-- en stays built-in: absent from the default languages table, still
-- configurable through setup(), literal-matching only.
local EN_DEFAULT = { enabled = true, filter_key = "<C-e>" }

M.config = {
	languages = {
		zhcn = { enabled = true, filter_key = "<C-c>" },
		ja = { enabled = true, filter_key = "<C-j>" },
		ko = { enabled = true, filter_key = "<C-k>" },
	},
	priority = { "zhcn", "ja", "ko" },
	mixed_input = true,
	-- integrations on flash-owned entry points (char: CJK-aware f/t/F/T)
	motions = { char = true },
}

---Normalizes one languages[lang] value: true -> enabled, false ->
---disabled, a table -> validated fields. Unknown fields are ignored
---(forward compatibility).
---@param lang string
---@param value boolean|table
---@return table normalized { enabled?, filter_key? }
function M.normalize_language(lang, value)
	if not vim.list_contains(LANGS, lang) then
		error("flash-cjk: unknown language code: " .. tostring(lang))
	end
	if value == true then
		return { enabled = true }
	elseif value == false then
		return { enabled = false }
	elseif type(value) ~= "table" then
		error(("flash-cjk: languages[%s] must be a boolean or table"):format(lang))
	end
	local normalized = {}
	for field, field_value in pairs(value) do
		if field == "enabled" then
			if type(field_value) ~= "boolean" then
				error(("flash-cjk: languages[%s].enabled must be a boolean"):format(lang))
			end
			normalized.enabled = field_value
		elseif field == "filter_key" then
			if type(field_value) ~= "string" and field_value ~= false then
				error(
					("flash-cjk: languages[%s].filter_key must be a string or false"):format(lang)
				)
			end
			normalized.filter_key = field_value
		end
	end
	return normalized
end

---Normalizes a motions value: known motion flags must be booleans (a
---non-boolean like the string "false" is truthy in Lua and would
---silently enable the integration). Unknown fields are ignored
---(forward compatibility).
---@param motions table
---@return table normalized { char?: boolean }
function M.normalize_motions(motions)
	local normalized = {}
	if motions.char ~= nil then
		if type(motions.char) ~= "boolean" then
			error("flash-cjk: motions.char must be a boolean")
		end
		normalized.char = motions.char
	end
	return normalized
end

---Base entry a language's setup() merge starts from: the built-in
---defaults for en, an empty table elsewhere (existing entries merge
---onto themselves).
---@param lang string
---@return table base
function M.language_base(lang)
	if lang == "en" then
		return EN_DEFAULT
	end
	return {}
end

---Boolean language flags for a languages config table, as consumed by
---the parser, labeler and the Rust bridge.
---@param languages table? defaults to M.config.languages
---@return table langs boolean flags
function M.lang_flags(languages)
	languages = languages or M.config.languages
	return {
		zhcn = languages.zhcn.enabled,
		ja = languages.ja.enabled,
		ko = languages.ko.enabled,
		en = (languages.en or EN_DEFAULT).enabled,
		mixed_input = M.config.mixed_input,
	}
end

---Flat filter-key map derived from a languages config table, as
---consumed by make_mix_mode and the labeler.
---@param languages table
---@return table keys lang -> key string (or false/unset)
function M.filter_keys(languages)
	local keys = {}
	for _, lang in ipairs(LANGS) do
		local entry = languages[lang] or EN_DEFAULT
		keys[lang] = entry.filter_key
	end
	return keys
end

---Resolves a jump/remote language argument into boolean language
---flags. nil or {} -> the setup-enabled set; otherwise the array fully
---decides the enabled set for this jump and overrides the setup
---switches.
---@param codes string[]? language codes, e.g. { "zhcn", "en" }
---@return table langs boolean flags
function M.resolve_langs(codes)
	if codes == nil or #codes == 0 then
		return M.lang_flags()
	end
	local langs = {
		zhcn = false,
		ja = false,
		ko = false,
		en = false,
		mixed_input = M.config.mixed_input,
	}
	for _, code in ipairs(codes) do
		if not vim.list_contains(LANGS, code) then
			error("flash-cjk: unknown language code: " .. tostring(code))
		end
		langs[code] = true
	end
	return langs
end

---Validates a priority list: elements must be known language codes;
---duplicates are meaningless and dropped (first occurrence wins).
---@param value string[] language codes in priority order
---@return string[] priority deduped
function M.normalize_priority(value)
	if type(value) ~= "table" then
		error("flash-cjk: priority must be an array of language codes")
	end
	local seen = {}
	local priority = {}
	for _, code in ipairs(value) do
		if not vim.list_contains(LANGS, code) then
			error("flash-cjk: unknown language code: " .. tostring(code))
		end
		if not seen[code] then
			seen[code] = true
			priority[#priority + 1] = code
		end
	end
	return priority
end

return M
