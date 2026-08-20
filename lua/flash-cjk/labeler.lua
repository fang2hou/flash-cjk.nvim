local lang = require("flash-cjk.lang")

local M = {}
M.__index = M

---@param state Flash.State
---@param langs table<string, boolean>? language flags, default all enabled
---@param force_keys table? per-jump force_keys override
---@param priority string[]? language codes in label-assignment priority order
function M.new(state, langs, force_keys, priority)
	local self
	self = setmetatable({}, M)
	self.state = state
	self.langs = langs or { zhcn = true, ja = true, ko = true, en = true }
	self.force_keys = force_keys
	if priority and #priority > 0 then
		-- ranks: listed languages get their list position, everything
		-- else ties on the trailing rank (filter()'s order stands among
		-- them); an empty list ranks nothing and stays unset
		self.lang_ranks = {}
		for i, lang in ipairs(priority) do
			self.lang_ranks[lang] = i
		end
		self.default_rank = #priority + 1
	end
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
	if self.lang_ranks then
		matches = self:sort_by_priority(matches)
	end

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
local SPELLING_LANGS = { "zhcn", "ja", "ko" } -- attribution order

function M:match_strs(line, start_col, end_col, langs)
	local size = char_size(line, end_col + 1)
	local text = string.sub(line, start_col, end_col + size)
	local strs = {}
	for _, code in ipairs(SPELLING_LANGS) do
		if langs[code] then
			vim.list_extend(strs, lang.get(code).strs(text))
		end
	end
	return strs
end

local function ascii_alnum(byte)
	return (byte >= 48 and byte <= 57) or (byte >= 65 and byte <= 90) or (byte >= 97 and byte <= 122)
end

-- Languages the current pattern could have reached `text` through:
-- each enabled engine that produces a spelling of `text` (the matched
-- text plus the character right after it, as in match_strs) extending
-- `prefix`; literal ASCII spans belong to "en". Mirrors the Rust
-- matcher's pred_langs tags.
---@param text string matched text plus the following character
---@param prefix string clean pattern (lock markers stripped)
---@param langs table<string, boolean> enabled language flags
---@return string[] langs attributed language codes
function M.match_langs(text, prefix, langs)
	local out = {}
	local first = string.byte(text)
	if first ~= nil and first < 128 then
		-- letters and digits only: the literal-matching domain. Engines
		-- pass ASCII through unchanged, so their spellings carry no
		-- language information for such spans.
		if langs.en and ascii_alnum(first) then
			out[1] = "en"
		end
		return out
	end
	local function extends(strs)
		for _, s in ipairs(strs) do
			if string.sub(s, 1, #prefix) == prefix then
				return true
			end
		end
		return false
	end
	for _, code in ipairs(SPELLING_LANGS) do
		if langs[code] and extends(lang.get(code).strs(text)) then
			out[#out + 1] = code
		end
	end
	return out
end

-- One match's language attribution: the cached Rust prediction tags
-- when the native path produced this match, otherwise the Lua spelling
-- expansion (mirrors skip()'s prediction/spelling split).
---@param m Flash.Match
---@param prefix string clean pattern
---@param line_cache table<string, string> win/line text cache
---@return string[]? langs nil when the match text is unavailable
function M:attribution(m, prefix, line_cache)
	local rust = package.loaded["flash-cjk.rust"]
	if rust and rust.available() then
		local preds = rust.predictions[m.win]
		local pred = preds and preds[string.format("%d:%d:%d", m.pos[1], m.pos[2], m.end_pos[2])]
		if pred then
			return pred.langs
		end
	end
	if m.pos[1] ~= m.end_pos[1] then
		return nil -- multi-line matches never reach the prediction path
	end
	local key = m.win .. ":" .. m.pos[1]
	local line = line_cache[key]
	if line == nil then
		local lines = vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(m.win), m.pos[1] - 1, m.pos[1], false)
		line = lines[1] or false
		line_cache[key] = line
	end
	if not line then
		return nil
	end
	-- the character right after the match is included, as the Rust
	-- predictor does (end_pos points at the last character's first
	-- byte, so the match's end byte needs the character size)
	local match_end = m.end_pos[2] + char_size(line, m.end_pos[2] + 1)
	local text = string.sub(line, m.pos[2] + 1, match_end + char_size(line, match_end + 1))
	return M.match_langs(text, prefix, self.langs)
end

-- Stable label-issuance order under the configured priority: matches
-- whose attribution includes a higher-priority language receive their
-- labels first; equal ranks keep filter()'s (win, position) order.
-- A language lock suspends the ordering: a locked jump matches
-- through exactly one language, so every rank is equal.
---@param matches Flash.Match[] filter() output
---@return Flash.Match[] matches ordered for label issuance
function M:sort_by_priority(matches)
	local clean, forced = require("flash-cjk.match").parse_forced(self.state.pattern.pattern, self.force_keys)
	if forced then
		return matches
	end
	local line_cache = {}
	local decorated = {}
	for i, m in ipairs(matches) do
		local rank = self.default_rank
		local langs = self:attribution(m, clean, line_cache)
		if langs then
			for _, lang in ipairs(langs) do
				local r = self.lang_ranks[lang]
				if r and r < rank then
					rank = r
				end
			end
		end
		decorated[i] = { rank, i, m }
	end
	table.sort(decorated, function(a, b)
		if a[1] ~= b[1] then
			return a[1] < b[1]
		end
		return a[2] < b[2]
	end)
	local out = {}
	for i, d in ipairs(decorated) do
		out[i] = d[3]
	end
	return out
end

-- Returns valid labels for the current search pattern in this window.
---@param labels string[]
---@return string[] returns labels to skip or `nil` when all labels should be skipped
function M:skip(win, labels)
	local prefix, forced = require("flash-cjk.match").parse_forced(self.state.pattern.pattern, self.force_keys)
	local prefix_len = string.len(prefix)
	local langs = self.langs
	if forced then
		langs = { zhcn = forced == "zhcn", ja = forced == "ja", ko = forced == "ko" }
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
				local pt = pred.text
				for i = 1, #pt do
					local char = string.sub(pt, i, i)
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
