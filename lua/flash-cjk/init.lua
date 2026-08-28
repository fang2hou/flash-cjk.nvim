-- Public API and orchestration. Configuration lives in config.lua, the
-- matching domain in match.lua, the flash.nvim patches in patches.lua;
-- this module wires them together and re-exports the public names.

local config = require("flash-cjk.config")
local match = require("flash-cjk.match")
local patches = require("flash-cjk.patches")

local M = {}

-- Re-exports: tests, e2e and user configs consume these from the
-- module root. `config` is an assignment-transparent alias of the
-- config module's state table.
M.resolve_langs = config.resolve_langs
M.make_mix_mode = match.make_mix_mode
M.parse_filter = match.parse_filter
setmetatable(M, {
	__index = function(_, key)
		if key == "config" then
			return config.config
		elseif key == "mix_mode" then
			-- built on first access: an eager build would load every
			-- language data table at startup, and the plugin itself only
			-- compiles per-jump modes in build_opts
			local mode = match.make_mix_mode(
				config.lang_flags(),
				config.filter_keys(config.config.languages)
			)
			rawset(M, "mix_mode", mode)
			return mode
		end
	end,
	__newindex = function(table, key, value)
		if key == "config" then
			config.config = value
			return
		end
		rawset(table, key, value)
	end,
})

local function get_flash()
	return require("flash")
end

local function build_opts(langs)
	local keys = config.filter_keys(M.config.languages)
	local mode = M.make_mix_mode(langs, keys)
	local actions = {}
	for _, lang in ipairs({ "zhcn", "ja", "ko", "en" }) do
		local key = keys[lang]
		if type(key) == "string" and key ~= "" then
			local marker = match.MARKER_BYTES[lang]
			actions[vim.api.nvim_replace_termcodes(key, true, true, true)] = function(state, _)
				-- a new lock replaces any previous one
				local clean = match.parse_filter(state.pattern.pattern)
				state:update({ pattern = clean .. marker })
				return true
			end
		end
	end
	-- C-c never reaches flash's actions (getcharstr raises an interrupt
	-- for it), so the patch below re-routes it -- but only while a C-c
	-- lock is configured; everything else keeps flash's behavior.
	patches.get_char_patch()
	patches.prompt_patch()
	patches.char_mode_patch()
	local defaults = {
		labels = "asdfghjklqwertyuiopzxcvbnm",
		search = {
			mode = mode,
		},
		actions = actions,
		labeler = function(_, state)
			require("flash-cjk.labeler").new(state, langs, keys, M.config.priority):update()
		end,
	}
	local rust_ok, rust = pcall(require, "flash-cjk.rust")
	if rust_ok and rust.available() then
		-- the binary replaces the vim-regex searcher entirely; failures
		-- fall back to it inside the bridge (rust.lua)
		defaults.matcher = rust.matcher(langs)
		rust.warmup() -- async, no-op without Unix/binary
	end
	return defaults
end

---Starts a flash jump with CJK matching.
---@param langs string[]? language codes for this jump, e.g. { "zhcn", "en" }
function M.jump(langs)
	get_flash().jump(build_opts(M.resolve_langs(langs)))
end

---Starts a flash remote (operator-pending) jump with CJK matching.
---@param langs string[]? language codes for this jump, e.g. { "zhcn", "en" }
function M.remote(langs)
	get_flash().remote(build_opts(M.resolve_langs(langs)))
end

---Configures the plugin. See the README (Language configuration,
---Mixed input) for the accepted fields and their semantics.
---@param opts table
function M.setup(opts)
	opts = opts or {}
	if opts.languages ~= nil then
		if type(opts.languages) ~= "table" then
			error("flash-cjk: languages must be a table")
		end
		for lang, value in pairs(opts.languages) do
			local normalized = config.normalize_language(lang, value)
			local base = M.config.languages[lang] or config.language_base(lang)
			M.config.languages[lang] = vim.tbl_deep_extend("force", {}, base, normalized)
		end
	end
	if type(opts.mixed_input) == "boolean" then
		M.config.mixed_input = opts.mixed_input
	end
	if opts.motions ~= nil then
		if type(opts.motions) ~= "table" then
			error("flash-cjk: motions must be a table")
		end
		M.config.motions = vim.tbl_deep_extend(
			"force",
			{},
			M.config.motions,
			config.normalize_motions(opts.motions)
		)
	end
	if opts.priority ~= nil then
		-- labeler-layer only: the mix mode does not read it
		M.config.priority = config.normalize_priority(opts.priority)
	end
	-- also installed here so ftFT is CJK-aware before the first jump:
	-- flash-cjk loads before flash's first f/F/t/T press
	patches.char_mode_patch()
end

return M
