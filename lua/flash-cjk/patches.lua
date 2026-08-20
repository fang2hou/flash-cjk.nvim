-- flash.nvim patches, installed by build_opts() in init.lua. Each patch
-- mutates flash only when a flash-cjk feature needs it.

local M = {}

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

-- Shows lock markers as readable [中]/[日]/[韩]/[英] tags in flash's
-- prompt instead of raw control bytes (^A, ^B, ...). Display only --
-- the pattern itself keeps its marker bytes.
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
			:gsub("\x04", " [韩]")
			:gsub("\x05", " [英]")
		return orig(display, show)
	end
end

return M
