-- flash.nvim patches: C-c dispatch and the prompt lock display. Both
-- are installed by build_opts() in init.lua and only mutate flash when
-- a flash-cjk feature needs them.

local M = {}

-- Swallows the C-c interrupt inside flash's input loop when (and only
-- when) the currently active flash state has a C-c language-lock action
-- registered (i.e. a flash-cjk jump with C-c bound). Plain flash jumps
-- keep their original behavior: the interrupt returns nil and exits.
function M.get_char_patch()
	local ok, Util = pcall(require, "flash.util")
	if not ok or type(Util.get_char) ~= "function" or Util._flash_cjk_patched then
		return
	end
	Util._flash_cjk_patched = true
	Util.get_char = function()
		local Hacks = require("flash.hacks")
		Hacks.setcursor()
		vim.cmd("redraw")
		local ok2, ret = pcall(vim.fn.getcharstr)
		if not ok2 then
			local okS, State = pcall(require, "flash.state")
			if okS then
				for state in pairs(State._states or {}) do
					-- only visible (actively looping) states: stale states
					-- kept alive by repeat references must not swallow C-c
					if state.visible
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
		return ret ~= Util.t("<esc>") and ret or nil
	end
end

-- Makes the lock state visible in flash's prompt: marker bytes would
-- render as raw control characters (^A, ^B...); they are shown as
-- readable [中]/[日]/[韩]/[英] tags instead. Only the display string
-- is transformed -- the real pattern keeps its marker bytes.
function M.prompt_patch()
	local ok, Prompt = pcall(require, "flash.prompt")
	if not ok or type(Prompt.set) ~= "function" or Prompt._flash_cjk_patched then
		return
	end
	Prompt._flash_cjk_patched = true
	local orig = Prompt.set
	Prompt.set = function(pattern, show)
		local display = pattern
			:gsub("\x01", " [中]")
			:gsub("\x02", " [日]")
			:gsub("\x04", " [韩]")
			:gsub("\x05", " [英]")
		return orig(display, show)
	end
end

return M
