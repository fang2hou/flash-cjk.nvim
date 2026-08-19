-- Rust matcher bridge: spawns the flash-cjk-search binary per keystroke
-- and falls back to flash's vim-regex searcher when the binary is
-- unavailable or keeps failing (circuit breaker).
--
-- The binary is built once via `cargo build --release` in rust/.

local M = {}

local bin ---@type string?
local disabled = false -- circuit breaker: set after repeated failures

local FAIL_LIMIT = 3
local fails = 0

-- Per-keystroke prediction cache filled by the matcher, keyed by
-- win -> "line:col:end" -> { text = <next letters>, langs = { <lang
-- codes> } } (labeler lookups carry the match's win); the labeler
-- consumes it instead of expanding spellings in Lua. `langs` holds
-- the attributed language codes of the match -- the interpretations
-- the current pattern could have taken (empty for punctuation and
-- when the binary predates the tags).
M.predictions = setmetatable({}, { __index = function(t, k)
	local v = {}
	rawset(t, k, v)
	return v
end })

local function find_bin()
	if bin ~= nil then
		return bin
	end
	local here = vim.fs.dirname(debug.getinfo(1, "S").source:sub(2))
	bin = vim.fs.normalize(here .. "/../../rust/target/release/flash-cjk-search") or ""
	return bin
end

---@return boolean true when the Rust matcher can be used
function M.available()
	if disabled then
		return false
	end
	local path = find_bin()
	return path ~= "" and vim.uv.fs_stat(path) ~= nil
end

---Runs the binary for one keystroke.
---@param pattern string raw pattern (lock markers included)
---@param lines string[] visible buffer lines
---@param langs table language flags
---@return table? response { matches = { {line,col,end_col,len}... }, predictions = { string... }, pred_langs = { { string... }... } }
function M.search(pattern, lines, langs)
	local path = find_bin()
	local req = vim.json.encode({
		pattern = pattern,
		lines = lines,
		langs = {
			zhcn = langs.zhcn and true or false,
			ja = langs.ja and true or false,
			ko = langs.ko and true or false,
			en = langs.en and true or false,
			alpha_mixing = langs.alpha_mixing ~= false,
		},
	})
	local ok, out = pcall(function()
		return vim.system({ path }, { stdin = req, timeout = 5000 }):wait()
	end)
	if not ok or not out or out.code ~= 0 then
		fails = fails + 1
		if fails >= FAIL_LIMIT then
			disabled = true
		end
		return nil
	end
	local okd, resp = pcall(vim.json.decode, out.stdout)
	if not okd or type(resp) ~= "table" or type(resp.matches) ~= "table" then
		fails = fails + 1
		if fails >= FAIL_LIMIT then
			disabled = true
		end
		return nil
	end
	fails = 0
	return resp
end

---flash matcher function backed by the Rust binary; any failure falls
---back to flash's default vim-regex searcher for that keystroke.
---@param langs table language flags captured by build_opts
---@return function matcher
function M.matcher(langs)
	return function(win, state, opts)
		local Pos = require("flash.search.pos")
		local fallback = function()
			return require("flash.search").new(win, state):get(opts)
		end
		if state.pattern:empty() then
			return {}
		end
		if not M.available() then
			return fallback()
		end
		local buf = vim.api.nvim_win_get_buf(win)
		opts = opts or {}
		local from = opts.from and opts.from[1]
			or vim.api.nvim_win_call(win, function()
				return vim.fn.line("w0")
			end)
		local to = opts.to and opts.to[1]
			or vim.api.nvim_win_call(win, function()
				-- w$ is the documented last visible line; "w1" is not a
				-- valid mark (line("w1") returns 0 on nvim >= 0.10) and
				-- yielded an empty range -- zero matches, no fallback
				return vim.fn.line("w$")
			end)
		local lines = vim.api.nvim_buf_get_lines(buf, from - 1, to, false)
		local resp = M.search(state.pattern.pattern, lines, langs)
		if resp == nil then
			-- binary failed: matches come from the fallback searcher,
			-- so this window's predictions belong to an older
			-- keystroke -- drop them (the labeler expands spellings in
			-- Lua when a prediction key is missing)
			M.predictions[win] = {}
			return fallback()
		end
		local matches = {}
		local keep = {}
		local found = resp.matches
		local preds = resp.predictions or {}
		local lang_tags = resp.pred_langs
		for i, m in ipairs(found) do
			-- Rust line indices are 0-based into the `lines` slice, which
			-- starts at buffer line `from` (visible top) -- convert to
			-- absolute buffer lines or flash's from/to filter drops
			-- everything once the window is scrolled.
			local line, col, end_col, len = m[1] + from, m[2], m[3], m[4]
			if len > 0 then
				matches[#matches + 1] = {
					win = win,
					pos = Pos({ line, col }),
					end_pos = Pos({ line, end_col }),
				}
				local key = string.format("%d:%d:%d", line, col, end_col)
				keep[key] = true
				M.predictions[win][key] = { text = preds[i] or "", langs = lang_tags and lang_tags[i] or {} }
			end
		end
		-- drop this window's stale predictions only: other windows are
		-- filled by their own matcher invocation
		for k in pairs(M.predictions[win]) do
			if not keep[k] then
				M.predictions[win][k] = nil
			end
		end
		return matches
	end
end


---Test hooks: trip / clear the circuit breaker.
function M.disable_for_test()
	disabled = true
end

function M.enable_for_test()
	disabled = false
	fails = 0
end
return M
