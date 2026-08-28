-- flash.nvim patches: C-c dispatch, prompt lock display, and the
-- CJK-aware char-motion and search-mode wraps. Installed by
-- build_opts() in init.lua -- the char and search wraps also by
-- setup(), ahead of flash's first f/F/t/T press or `/` search. Each
-- patch mutates flash only when a flash-cjk feature needs it.

local M = {}

local config = require("flash-cjk.config")
local match = require("flash-cjk.match")

-- Swallows the C-c interrupt inside flash's input loop while the
-- active flash state has a C-c language-lock action registered (plain
-- flash jumps keep the original behavior: the interrupt exits).
function M.get_char_patch()
	local ok, Util = pcall(require, "flash.util")
	if not ok or type(Util.get_char) ~= "function" or Util._flash_cjk_patched then
		return
	end
	-- markers on flash's module; the guard above makes them idempotent
	---@diagnostic disable-next-line: inject-field
	Util._flash_cjk_patched = true
	---@diagnostic disable-next-line: duplicate-set-field
	Util.get_char = function()
		local Hacks = require("flash.hacks")
		Hacks.setcursor()
		vim.cmd("redraw")
		local interrupted, char = pcall(vim.fn.getcharstr)
		if not interrupted then
			local has_state, State = pcall(require, "flash.state")
			if has_state then
				for state in pairs(State._states or {}) do
					-- only visible (actively looping) states: stale ones
					-- kept alive by repeat references must not swallow C-c
					if
						state.visible
						and state.opts
						and state.opts.actions
						and state.opts.actions["\x03"]
					then
						return "\x03"
					end
				end
			end
			return nil
		end
		return char ~= Util.t("<esc>") and char or nil
	end
end

-- Shows lock markers as readable tags in flash's prompt instead of
-- raw control bytes (^A, ^B, ...). Each language is tagged in its own
-- script: [中] [日] [한] [EN]. Display only -- the pattern itself
-- keeps its marker bytes.
function M.prompt_patch()
	local ok, Prompt = pcall(require, "flash.prompt")
	if not ok or type(Prompt.set) ~= "function" or Prompt._flash_cjk_patched then
		return
	end
	---@diagnostic disable-next-line: inject-field
	Prompt._flash_cjk_patched = true
	local orig = Prompt.set
	---@diagnostic disable-next-line: duplicate-set-field
	Prompt.set = function(pattern, show)
		local display = pattern
			:gsub("\x01", " [中]")
			:gsub("\x02", " [日]")
			:gsub("\x04", " [한]")
			:gsub("\x05", " [EN]")
		return orig(display, show)
	end
end

-- Makes flash's enhanced f/t/F/T motions (modes.char) CJK-aware: the
-- single typed character is compiled through the mix mode, so pinyin,
-- romaji and romanization first letters and CJK punctuation classes
-- match CJK characters too. f/F search the target itself, t the char
-- before it and T the char after it -- exactly where the native
-- motions land.
function M.char_mode_patch()
	local ok, Char = pcall(require, "flash.plugins.char")
	if not ok or type(Char.mode) ~= "function" or Char._flash_cjk_patched then
		return
	end
	---@diagnostic disable-next-line: inject-field
	Char._flash_cjk_patched = true
	local orig = Char.mode
	---@diagnostic disable-next-line: duplicate-set-field
	Char.mode = function(motion)
		local native = orig(motion)
		return function(c)
			if not config.config.motions.char then
				return native(c)
			end
			-- compiled per input, so setup() changes are always honored
			local cjk = match.make_mix_mode(
				config.lang_flags(),
				config.filter_keys(config.config.languages)
			)(c)
			local pattern
			if motion == "t" then
				-- match the char right before the target (native: \m.\ze\V<c>)
				pattern = "\\m.\\ze" .. cjk
			elseif motion == "T" then
				-- match the char right after the target (native: \V<c>\zs\m.)
				pattern = "\\m" .. cjk .. "\\zs."
			else
				pattern = cjk -- f/F: the target itself
			end
			-- flash's stubs type Config.get strictly and do not know the
			-- char mode's fields; the call mirrors char.lua's own usage
			---@diagnostic disable-next-line: param-type-mismatch, undefined-field
			if not require("flash.config").get("char").multi_line then
				local pos = vim.api.nvim_win_get_cursor(0)
				pattern = ("\\%%%dl"):format(pos[1]) .. pattern
			end
			return pattern
		end
	end
end

-- Native vim regex keeps its contract: metacharacters (the magic
-- set), the search delimiter, and non-ASCII bytes (IME input) pass
-- through untouched; only plain-text queries go through the mix
-- compiler. Trade-off: punctuation-class CJK matching in `/` covers
-- only the non-meta keys , ; ' " : ! - -- the s-jump keeps the full
-- set (there . [ ] ? are matchable too).
local function native_regex(query)
	return query:find("[\\.%[%]^$~/*]") ~= nil or query:find("[\128-\255]") ~= nil
end

-- Makes flash's search mode (modes.search: `/` and `?` with flash's
-- label overlay) CJK-aware: every cmdline change recompiles the whole
-- query through the mix mode, so pinyin/romaji input matches CJK
-- characters; typing a label char jumps through flash's own
-- check_jump. <cr>/n/N keep native semantics. Queries that look like
-- regex (see native_regex) pass through verbatim -- flash's
-- operator-pending `\%<line>l\%<col>c.` rewrite relies on that too.
function M.search_mode_patch()
	local ok, Search = pcall(require, "flash.plugins.search")
	if not ok or type(Search.start) ~= "function" or Search._flash_cjk_patched then
		return
	end
	---@diagnostic disable-next-line: inject-field
	Search._flash_cjk_patched = true
	local orig = Search.start
	---@diagnostic disable-next-line: duplicate-set-field
	Search.start = function()
		orig()
		local state = Search.state
		if not config.config.motions.search or not state then
			return
		end
		-- compiled per start, so setup() changes are always honored
		local flags = config.lang_flags()
		local keys = config.filter_keys(config.config.languages)
		local mix = match.make_mix_mode(flags, keys)
		-- State.new bakes the hardcoded mode string and the default
		-- labeler into plain fields; both are swapped post-construction
		state.pattern.mode = function(str)
			if native_regex(str) then
				return str
			end
			return mix(str)
		end
		-- unlike char mode, queries are multi-char: a typed
		-- continuation letter could collide with an assigned label, so
		-- the flash-cjk labeler (which predicts and skips likely next
		-- letters) must replace flash's default here
		state.labeler = function(_, st)
			require("flash-cjk.labeler").new(st, flags, keys, config.config.priority):update()
		end
	end
end

return M
