-- flash-cjk entry point: public API and orchestration. Configuration
-- lives in config.lua, the matching domain in match.lua and the
-- flash.nvim patches in patches.lua; this module wires them together
-- and re-exports the public names.

local config = require("flash-cjk.config")
local match = require("flash-cjk.match")
local patches = require("flash-cjk.patches")

local M = {}

-- Re-exports: tests, e2e and user configs consume these from the
-- module root. `config` is an assignment-transparent alias of the
-- config module's state table: both reads and rebinding
-- (fc.config = {...}) keep pointing at the live state, as they did
-- before the split.
M.resolve_langs = config.resolve_langs
M.make_mix_mode = match.make_mix_mode
M.parse_forced = match.parse_forced
setmetatable(M, {
	__index = function(_, k)
		if k == "config" then
			return config.config
		end
	end,
	__newindex = function(t, k, v)
		if k == "config" then
			config.config = v
			return
		end
		rawset(t, k, v)
	end,
})

-- flash.nvim is only needed when actually jumping.
local function get_flash()
	return require("flash")
end

-- Default mixed mode: every enabled language, default force keys.
M.mix_mode = M.make_mix_mode(config.lang_flags(), config.force_keys(M.config.languages))

local function build_opts(langs, opts)
	local keys = config.force_keys(config.effective_languages(opts))
	local mode = M.make_mix_mode(langs, keys)
	local actions = {}
	for _, lang in ipairs({ "zhcn", "ja", "ko", "en" }) do
		local key = keys[lang]
		if type(key) == "string" and key ~= "" then
			local marker = match.MARKER_BYTES[lang]
			actions[vim.api.nvim_replace_termcodes(key, true, true, true)] = function(state, _)
				state:update({ pattern = state.pattern:extend(marker) })
				return true
			end
		end
	end
	-- C-c never reaches flash's actions: getcharstr raises an interrupt
	-- for it. Patch Util.get_char so that the interrupt is swallowed and
	-- the raw byte is returned for action dispatch -- but only while a
	-- C-c language lock is actually configured; everything else keeps
	-- flash's original behavior.
	patches.get_char_patch()
	patches.prompt_patch()
	-- Rust fast path: when the binary exists it replaces the vim-regex
	-- searcher entirely; per-keystroke failures fall back to the default
	-- searcher inside the bridge (see lua/flash-cjk/rust.lua)
	local defaults = {
		labels = "asdfghjklqwertyuiopzxcvbnm",
		search = {
			mode = mode,
		},
		actions = actions,
		labeler = function(_, state)
			require("flash-cjk.labeler").new(state, langs, keys, config.effective_priority(opts)):update()
		end,
	}
	local rust_ok, rust = pcall(require, "flash-cjk.rust")
	if rust_ok and rust.available() then
		defaults.matcher = rust.matcher(langs)
		-- warm the persistent server (async, no-op without Unix/binary)
		rust.warmup()
	end
	return vim.tbl_deep_extend("force", defaults, opts)
end

---Starts a flash jump with CJK matching.
---@param langs string[]? language codes for this jump, e.g. { "zhcn", "en" }
---@param opts table? flash options (plus languages and priority overrides)
function M.jump(langs, opts)
	opts = opts or {}
	get_flash().jump(build_opts(M.resolve_langs(langs, opts), opts))
end

---Starts a flash remote (operator-pending) jump with CJK matching.
---@param langs string[]? language codes for this jump, e.g. { "zhcn", "en" }
---@param opts table? flash options (plus languages and priority overrides)
function M.remote(langs, opts)
	opts = opts or {}
	get_flash().remote(build_opts(M.resolve_langs(langs, opts), opts))
end

-- @param opts table
-- @field[opt] opts.languages table Per-language config, deep-merged
--   into the defaults: { zhcn = { enabled = true, scheme =
--   "xiaohe", force_key = "<C-c>" }, ja = ..., ko = ..., en = {
--   force_key = "<C-e>" } }; entries also accept the true/false
--   shorthand.
-- @field[opt] opts.alpha_mixing boolean Allow mixing literal letters into language chains.
-- @field[opt] opts.priority string[] Language codes in label-assignment
--   priority order, e.g. { "ja", "zhcn" }: matches reachable through
--   earlier-listed languages receive their labels first (match sets
--   and jump semantics unchanged; unset keeps position order).
function M.setup(opts)
	opts = opts or {}
	local dirty = false
	if opts.languages ~= nil then
		if type(opts.languages) ~= "table" then
			error("flash-cjk: languages must be a table")
		end
		for lang, value in pairs(opts.languages) do
			local norm = config.normalize_language(lang, value)
			M.config.languages[lang] = vim.tbl_deep_extend("force", {}, M.config.languages[lang], norm)
			dirty = true
		end
	end
	if type(opts.alpha_mixing) == "boolean" then
		M.config.alpha_mixing = opts.alpha_mixing
		dirty = true
	end
	if opts.priority ~= nil then
		-- labeler-layer only: the mix mode does not read it
		M.config.priority = config.normalize_priority(opts.priority)
	end
end

return M
