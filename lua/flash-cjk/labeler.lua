local pinyin = require("flash-cjk.pinyin")

local M = {}
M.__index = M

---@param state Flash.State
---@param langs table<string, boolean>? language flags, default all enabled
---@param force_keys table? per-jump force_keys override
function M.new(state, langs, force_keys)
	local self
	self = setmetatable({}, M)
	self.state = state
	self.langs = langs or { cn = true, jp = true, ko = true, en = true }
	self.force_keys = force_keys
	self.used = {}
	self:reset()
	return self
end

function M:update()
	self:reset()

	if #self.state.pattern() < self.state.opts.label.min_pattern_length then
		return
	end

	local matches = self:filter()

	for _, match in ipairs(matches) do
		self:label(match, true)
	end

	for _, match in ipairs(matches) do
		if not self:label(match) then
			break
		end
	end
end

local char_size = require("flash-cjk.util").char_size

-- All spellings the matched text (plus the character right after it,
-- so that a pattern covering the match exactly still predicts the next
-- input letter) could have been typed as.
function M:match_strs(line, start_col, end_col, langs)
	local size = char_size(line, end_col + 1)
	local text = string.sub(line, start_col, end_col + size)
	local strs = {}
	if langs.cn then
		vim.list_extend(strs, pinyin.pinyin(text))
	end
	if langs.jp then
		vim.list_extend(strs, require("flash-cjk.jp").romaji_strs(text))
	end
	if langs.ko then
		vim.list_extend(strs, require("flash-cjk.ko").strs(text))
	end
	return strs
end

-- Returns valid labels for the current search pattern in this window.
---@param labels string[]
---@return string[] returns labels to skip or `nil` when all labels should be skipped
function M:skip(win, labels)
	local prefix, forced = require("flash-cjk.match").parse_forced(self.state.pattern.pattern, self.force_keys)
	local prefix_len = string.len(prefix)
	local langs = self.langs
	if forced then
		langs = { cn = forced == "cn", jp = forced == "jp", ko = forced == "ko" }
	end
	-- The per-match filter loops below cumulatively remove every label
	-- that equals a predicted next letter of ANY match: collect the
	-- union set first and filter the label pool once.
	local ignorecase = vim.go.ignorecase
	local skip_set = {}
	local buf = nil
	local line_cache = {}
	local rust = package.loaded["flash-cjk.rust"]
	local rust_on = rust and rust.available()
	local preds = rust_on and rust.predictions[win] or nil
	for _, match in ipairs(self.state.results) do
		if match.win == win then
			buf = buf or vim.api.nvim_win_get_buf(match.win)
			local start_line, end_line = match.pos[1], match.end_pos[1]
			if start_line ~= end_line then
				goto continue
			end

			local line = line_cache[start_line]
			if line == nil then
				local lines = vim.api.nvim_buf_get_lines(buf, start_line - 1, end_line, false)
				if #lines == 0 then
					goto continue
				end
				line = lines[1]
				line_cache[start_line] = line
			end
			local start_col, end_col = match.pos[2] + 1, match.end_pos[2] + 2

			-- Rust fast path: predictions were computed alongside the
			-- matches; use them instead of expanding spellings in Lua
			local pred = preds and preds[string.format("%d:%d:%d", match.pos[1], match.pos[2], match.end_pos[2])]
			if pred then
				for i = 1, #pred do
					local char = string.sub(pred, i, i)
					skip_set[ignorecase and char:lower() or char] = true
				end
			else
				local strs = self:match_strs(line, start_col, end_col, langs)
				for i = 1, #strs do
					local char = string.sub(strs[i], prefix_len + 1, prefix_len + 1)
					if char ~= "" then
						skip_set[ignorecase and char:lower() or char] = true
					end
				end
			end
		end
		::continue::
	end
	return vim.tbl_filter(function(c)
		return not skip_set[ignorecase and c:lower() or c]
	end, labels)
end

function M:reset()
	local skip = {} ---@type table<string, boolean>
	self.labels = {}

	for _, l in ipairs(self.state:labels()) do
		if not skip[l] then
			self.labels[#self.labels + 1] = l
			skip[l] = true
		end
	end
	if not self.state.opts.search.max_length or #self.state.pattern() < self.state.opts.search.max_length then
		for _, win in pairs(self.state.wins) do
			self.labels = self:skip(win, self.labels)
		end
	end
	-- pool bookkeeping for the monotonic assignment pointer: valid() must
	-- still reject labels removed by skip() this keystroke (reuse case)
	self.pool_set = {}
	for _, l in ipairs(self.labels) do
		self.pool_set[l] = true
	end
	self.used_labels = {}
	self.next_label = 1
	for _, m in ipairs(self.state.results) do
		if m.label ~= false then
			m.label = nil
		end
	end
end

function M:valid(label)
	return self.pool_set[label] and not self.used_labels[label]
end

---Assignments within one update are monotonic (the pool never gives a
---label back), so a start index replaces per-assignment array filtering.
---@param m Flash.Match
---@param used boolean?
function M:label(m, used)
	if m.label ~= nil then
		return true
	end
	local pos = m.pos:id(m.win)
	local label ---@type string?
	if used then
		label = self.used[pos]
	else
		while self.next_label <= #self.labels do
			local candidate = self.labels[self.next_label]
			if not self.used_labels[candidate] then
				break
			end
			self.next_label = self.next_label + 1
		end
		label = self.labels[self.next_label]
	end
	if label and self:valid(label) then
		self.used_labels[label] = true
		if not used then
			self.next_label = self.next_label + 1
		end
		local reuse = self.state.opts.label.reuse == "all"
			or (self.state.opts.label.reuse == "lowercase" and label:lower() == label)

		if reuse then
			self.used[pos] = label
		end
		m.label = label
	end
	return self.next_label <= #self.labels
end

function M:filter()
	---@type Flash.Match[]
	local ret = {}

	local target = self.state.target

	local from = vim.api.nvim_win_get_cursor(self.state.win)
	---@type table<number, boolean>
	local folds = {}

	-- only label visible matches
	for _, match in ipairs(self.state.results) do
		-- and don't label the first match in the current window
		local skip = (target and match.pos == target.pos)
			and not self.state.opts.label.current
			and match.win == self.state.win

		-- Only label the first match in each fold
		if not skip and match.fold then
			if folds[match.fold] then
				skip = true
			else
				folds[match.fold] = true
			end
		end

		if not skip then
			table.insert(ret, match)
		end
	end

	-- sort by current win, other win, then by distance
	table.sort(ret, function(a, b)
		local use_distance = self.state.opts.label.distance and a.win == self.state.win

		if a.win ~= b.win then
			local aw = a.win == self.state.win and 0 or a.win
			local bw = b.win == self.state.win and 0 or b.win
			return aw < bw
		end
		if use_distance then
			local dfrom = from[1] * vim.go.columns + from[2]
			local da = a.pos[1] * vim.go.columns + a.pos[2]
			local db = b.pos[1] * vim.go.columns + b.pos[2]
			return math.abs(dfrom - da) < math.abs(dfrom - db)
		end
		if a.pos[1] ~= b.pos[1] then
			return a.pos[1] < b.pos[1]
		end
		return a.pos[2] < b.pos[2]
	end)
	return ret
end

return M
