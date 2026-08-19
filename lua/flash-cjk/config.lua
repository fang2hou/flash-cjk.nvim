-- Configuration state: defaults, the scheme registry and language-flag
-- resolution. Zero flash.nvim dependency -- init.lua's setup() writes
-- into M.config and rebuilds the module-level mix mode on change.

local M = {}

-- Default configuration: every language is enabled. Each entry can be
-- tuned via setup():
--   cn/jp/ko      true (default scheme), false, or a scheme name
--                 (see SCHEMES below: cn "xiaohe", jp/ko "roma")
--   en            literal ASCII letters, i.e. plain flash.nvim behavior
--   alpha_mixing  false additionally drops interpretations that mix
--                 literal letters with language segments (e.g. alpha
--                 "n" + pinyin "i"); the original flash-zh behavior
--                 keeps them; turning mixing off trades some
--                 mixed-chain reachability (e.g. pinyin "nihao"
--                 variants) for lower regex cost on long inputs;
--                 measure before enabling.
-- Per-jump overrides take an array of language codes instead, e.g.
-- jump({ "cn", "en" }) -- see M.resolve_langs.
M.config = {
	cn = "xiaohe",
	jp = "roma",
	ko = "roma",
	en = true,
	alpha_mixing = true,
	-- Keys that lock matching to a single language mid-input. The raw
	-- key bytes are never stored in the pattern; each lock writes a
	-- buffer-safe internal marker instead (C-j's newline would break
	-- flash's prompt). C-c's interrupt is intercepted and dispatched to
	-- the lock action while a flash-cjk jump is active.
	force_keys = {
		cn = "<C-c>",
		jp = "<C-j>",
		ko = "<C-k>",
		en = "<C-e>",
	},
}

-- Registered matching schemes per language. Each language currently
-- ships exactly one scheme: the string validates and records the
-- choice without changing matching behavior (future schemes plug in
-- here).
local SCHEMES = {
	cn = { default = "xiaohe", xiaohe = true },
	jp = { default = "roma", roma = true },
	ko = { default = "roma", roma = true },
}

---Normalizes a setup value for cn/jp/ko: true -> the default scheme
---name, a string -> the validated scheme, false -> false.
---@param lang string
---@param value boolean|string
---@return string|false
function M.normalize_lang(lang, value)
	if value == true then
		return SCHEMES[lang].default
	elseif type(value) == "string" then
		if SCHEMES[lang][value] then
			return value
		end
		error(("flash-cjk: unknown %s scheme %q"):format(lang, value))
	elseif value == false then
		return false
	end
	error(("flash-cjk: %s must be a boolean or scheme string"):format(lang))
end

---Boolean language flags derived from config, as consumed by the
---parser, labeler and the Rust bridge (cn/jp/ko are enabled unless
---the scheme is explicitly false).
---@return table langs boolean flags
function M.lang_flags()
	return {
		cn = M.config.cn ~= false,
		jp = M.config.jp ~= false,
		ko = M.config.ko ~= false,
		en = M.config.en,
		alpha_mixing = M.config.alpha_mixing,
	}
end

---Resolves a jump/remote language array into boolean language flags.
---nil or {} -> the setup-enabled set; otherwise the array fully
---decides the enabled set for this jump ("kr" is an alias of "ko";
---alpha_mixing always comes from config).
---@param ary string[]? language codes, e.g. { "cn", "en" }
---@return table langs boolean flags
function M.resolve_langs(ary)
	if ary == nil or #ary == 0 then
		return M.lang_flags()
	end
	local langs = { cn = false, jp = false, ko = false, en = false, alpha_mixing = M.config.alpha_mixing }
	for _, code in ipairs(ary) do
		local lang = code == "kr" and "ko" or code
		if lang ~= "cn" and lang ~= "jp" and lang ~= "ko" and lang ~= "en" then
			error("flash-cjk: unknown language code: " .. tostring(code))
		end
		langs[lang] = true
	end
	return langs
end

return M
