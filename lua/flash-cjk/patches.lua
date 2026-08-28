-- flash.nvim patches: C-c dispatch, prompt lock display, and the
-- CJK-aware char-motion mode wrap. Installed by build_opts() in
-- init.lua -- the char wrap also by setup(), ahead of flash's first
-- f/F/t/T press. Each patch mutates flash only when a flash-cjk
-- feature needs it.

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

return M
