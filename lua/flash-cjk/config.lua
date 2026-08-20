-- Configuration state: defaults, the scheme registry and language-flag
-- resolution. Zero flash.nvim dependency -- init.lua's setup() writes
-- into M.config and rebuilds the module-level mix mode on change.

local M = {}

-- Language codes in marker/action order.
local LANGS = { "zhcn", "ja", "ko", "en" }

-- Default configuration: every language is enabled. Each languages
-- entry tunes one language (deep-merged by setup; unspecified fields
-- keep their current value):
--   enabled   boolean; the entry also accepts the true/false shorthand
--   scheme    "xiaohe" for zhcn, "roma" for ja/ko (see SCHEMES);
--             en matches literal ASCII, has no scheme concept and
--             errors if given one
--   force_key key locking matching to this language mid-input; the raw
--             key bytes are never stored in the pattern, each lock
--             writes a buffer-safe internal marker instead (C-j's
--             newline would break flash's prompt). C-c's interrupt is
--             intercepted and dispatched to the lock action while a
--             flash-cjk jump is active. false disables the lock.
-- mixed_input (top level): false forbids an interpretation from
--   returning to literal letters after a language segment -- literal
--   heads stay allowed, pure-language and pure-literal chains are
--   unaffected, so only targets like text "日n" (language followed by
--   literal) lose reachability; the default keeps every mixed chain;
--   turning it off trades that reachability for lower regex cost on
--   long inputs; measure before disabling.
-- Per-jump override: jump({ "zhcn", "en" }) is the enabled-set
-- shorthand -- see M.resolve_langs.
-- priority (top level): array of language codes, e.g.
--   { "ja", "zhcn" }; matches reachable through earlier-listed
--   languages receive their labels first, so targets in the
--   prioritized language sit on the earliest labels. Label
--   assignment order only -- match sets and jump semantics are
--   unchanged, and unset (the default) keeps plain position order.
M.config = {
	languages = {
		zhcn = { enabled = true, scheme = "xiaohe", force_key = "<C-c>" },
		ja = { enabled = true, scheme = "roma", force_key = "<C-j>" },
		ko = { enabled = true, scheme = "roma", force_key = "<C-k>" },
		en = { enabled = true, force_key = "<C-e>" },
	},
	mixed_input = true,
}

-- Registered matching schemes per language. Each language currently
-- ships exactly one scheme: the string validates and records the
-- choice without changing matching behavior (future schemes plug in
-- here).
local SCHEMES = {
	zhcn = { default = "xiaohe", xiaohe = true },
	ja = { default = "roma", roma = true },
	ko = { default = "roma", roma = true },
}

---Normalizes one languages[lang] value: true -> enabled with the
---default scheme, false -> disabled, a table -> validated fields.
---@param lang string
---@param value boolean|table
---@return table normalized { enabled?, scheme?, force_key? }
function M.normalize_language(lang, value)
	if not vim.list_contains(LANGS, lang) then
		error("flash-cjk: unknown language code: " .. tostring(lang))
	end
	if value == true then
		local norm = { enabled = true }
		if SCHEMES[lang] then
			norm.scheme = SCHEMES[lang].default
		end
		return norm
	elseif value == false then
		return { enabled = false }
	elseif type(value) ~= "table" then
		error(("flash-cjk: languages[%s] must be a boolean or table"):format(lang))
	end
	local norm = {}
	for field, v in pairs(value) do
		if field == "enabled" then
			if type(v) ~= "boolean" then
				error(("flash-cjk: languages[%s].enabled must be a boolean"):format(lang))
			end
			norm.enabled = v
		elseif field == "scheme" then
			if not SCHEMES[lang] then
				error(("flash-cjk: languages[%s] has no scheme concept"):format(lang))
			end
			if type(v) ~= "string" or not SCHEMES[lang][v] then
				error(("flash-cjk: unknown %s scheme %q"):format(lang, tostring(v)))
			end
			norm.scheme = v
		elseif field == "force_key" then
			if type(v) ~= "string" and v ~= false then
				error(("flash-cjk: languages[%s].force_key must be a string or false"):format(lang))
			end
			norm.force_key = v
		end
		-- unknown fields are ignored: forward compatibility
	end
	return norm
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
---flags. nil or {} -> the setup-enabled set; otherwise the array is
---the enabled-set shorthand: it fully decides the enabled set for
---this jump (schemes fall back to each language's default) and
---overrides the setup switches.
---@param ary string[]? language codes, e.g. { "zhcn", "en" }
---@return table langs boolean flags
function M.resolve_langs(ary)
	if ary == nil or #ary == 0 then
		return M.lang_flags()
	end
	local langs = {
		zhcn = false,
		ja = false,
		ko = false,
		en = false,
		mixed_input = M.config.mixed_input,
	}
	for _, code in ipairs(ary) do
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
	local out = {}
	for _, code in ipairs(value) do
		if not vim.list_contains(LANGS, code) then
			error("flash-cjk: unknown language code: " .. tostring(code))
		end
		if not seen[code] then
			seen[code] = true
			out[#out + 1] = code
		end
	end
	return out
end

return M
