-- Configuration state: defaults, the scheme registry and language-flag
-- resolution. No flash.nvim dependency -- setup() writes into M.config
-- and the mix mode is rebuilt from it on change. Field semantics are
-- documented in the README (Language configuration, Mixed input).

local M = {}

local LANGS = { "zhcn", "ja", "ko", "en" }

M.config = {
	languages = {
		zhcn = { enabled = true, scheme = "xiaohe", force_key = "<C-c>" },
		ja = { enabled = true, scheme = "roma", force_key = "<C-j>" },
		ko = { enabled = true, scheme = "roma", force_key = "<C-k>" },
		en = { enabled = true, force_key = "<C-e>" },
	},
	mixed_input = true,
}

-- Registered schemes per language; each language currently ships
-- exactly one, so the string only validates and records the choice.
local SCHEMES = {
	zhcn = { default = "xiaohe", xiaohe = true },
	ja = { default = "roma", roma = true },
	ko = { default = "roma", roma = true },
}

---Normalizes one languages[lang] value: true -> enabled with the
---default scheme, false -> disabled, a table -> validated fields.
---Unknown fields are ignored (forward compatibility).
---@param lang string
---@param value boolean|table
---@return table normalized { enabled?, scheme?, force_key? }
function M.normalize_language(lang, value)
	if not vim.list_contains(LANGS, lang) then
		error("flash-cjk: unknown language code: " .. tostring(lang))
	end
	if value == true then
		local normalized = { enabled = true }
		if SCHEMES[lang] then
			normalized.scheme = SCHEMES[lang].default
		end
		return normalized
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
		elseif field == "scheme" then
			if not SCHEMES[lang] then
				error(("flash-cjk: languages[%s] has no scheme concept"):format(lang))
			end
			if type(field_value) ~= "string" or not SCHEMES[lang][field_value] then
				error(("flash-cjk: unknown %s scheme %q"):format(lang, tostring(field_value)))
			end
			normalized.scheme = field_value
		elseif field == "force_key" then
			if type(field_value) ~= "string" and field_value ~= false then
				error(("flash-cjk: languages[%s].force_key must be a string or false"):format(lang))
			end
			normalized.force_key = field_value
		end
	end
	return normalized
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
		en = languages.en.enabled,
		mixed_input = M.config.mixed_input,
	}
end

---Flat force-key map derived from a languages config table, as
---consumed by make_mix_mode and the labeler.
---@param languages table
---@return table keys lang -> key string (or false/unset)
function M.force_keys(languages)
	local keys = {}
	for _, lang in ipairs(LANGS) do
		keys[lang] = languages[lang].force_key
	end
	return keys
end

---Resolves a jump/remote language argument into boolean language
---flags. nil or {} -> the setup-enabled set; otherwise the array fully
---decides the enabled set for this jump (schemes fall back to each
---language's default) and overrides the setup switches.
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
