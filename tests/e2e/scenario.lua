-- E2E scenario driven by repro.lua inside the isolated lazy.nvim env:
-- real flash-cjk jumps through the lazy-loaded plugin, pass/fail lines
-- written to $FLASH_CJK_E2E_OUT (file signal: UI plugins like noice
-- swallow :lua output, so results go to a file). Run:
--   tests/e2e/run.sh

local out_path = assert(os.getenv("FLASH_CJK_E2E_OUT"), "FLASH_CJK_E2E_OUT required")
local out = assert(io.open(out_path, "w"))

local passed, failed = 0, 0
local function ok(cond, msg)
	if cond then
		passed = passed + 1
		out:write("ok " .. msg .. "\n")
	else
		failed = failed + 1
		out:write("FAIL " .. msg .. "\n")
	end
	out:flush() -- survive a killed run: the file is the only signal
end

local function finish()
	out:write(("SUMMARY %d %d\n"):format(passed, failed))
	out:close()
	vim.cmd("qa!")
end

-- 1. lazy.nvim installed and can load the spec.
vim.cmd("Lazy load flash-cjk.nvim")
local fc = require("flash-cjk")
ok(
	type(fc.jump) == "function" and type(fc.remote) == "function",
	"lazy load: flash-cjk module resolves"
)

ok(
	fc.config.languages.zhcn.filter_key == "<C-c>" and fc.config.languages.ja.filter_key == "<C-j>",
	"opts: lazy opts normalized with filter keys"
)

local rust = require("flash-cjk.rust")
local no_rust = os.getenv("FLASH_CJK_E2E_NO_RUST") == "1"
if no_rust then
	rust.disable_for_test()
end
ok(rust.available() ~= no_rust, "rust path: availability matches requested mode")

-- warm the persistent server before the jumps so the transport under
-- test is deterministic (live usage warms on the first jump)
if not no_rust then
	rust.warmup()
	vim.wait(2000, function()
		return rust.server_ready()
	end, 10)
end

-- 2. Real jump in a real buffer, driven through prefed typeahead (the
-- flash loop consumes nvim_input-queued keys, same technique as
-- tests/run.lua). jump() takes no options, so last_state is captured
-- by wrapping the labeler module's constructor: build_opts re-quires
-- the same cached table, and the wrapper chains into flash-cjk's own
-- labeler, so behavior under test is exactly build_opts' default.
local last_state ---@type Flash.State?
local labeler_mod = require("flash-cjk.labeler")
local labeler_new = labeler_mod.new
-- capture hook: replaces flash-cjk's own constructor for this scenario
---@diagnostic disable-next-line: duplicate-set-field
labeler_mod.new = function(state, ...)
	last_state = state
	return labeler_new(state, ...)
end

local function run(prefed)
	vim.api.nvim_input(prefed)
	return pcall(fc.jump)
end

vim.cmd("enew!")
local lines = { "日本語テスト ち 梯 안녕", "hello 日本" }
vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
vim.api.nvim_win_set_cursor(0, { 1, 0 })

local function char_at(m)
	local pos = m.pos or {}
	local line = lines[pos[1] or 0]
	if not line then
		return ""
	end
	return line:sub((pos[2] or -1) + 1, (pos[2] or -1) + 3) -- CJK: 3 bytes
end

-- plain trilingual jump: ti -> ち (jp romaji) + 梯 (zh pinyin)
last_state = nil
local ok_run, err = run("ti<cr>")
ok(
	ok_run and err == nil,
	"jump ti: loop completed without error" .. (err and (": " .. tostring(err)) or "")
)

if last_state and last_state.results then
	local saw_ch, saw_ti = false, false
	for _, m in ipairs(last_state.results) do
		local ch = char_at(m)
		if ch == "ち" then
			saw_ch = true
		end
		if ch == "梯" then
			saw_ti = true
		end
	end
	ok(saw_ch and saw_ti, "jump ti: matched both ち (jp) and 梯 (zh)")

	-- cursor landed on the accepted match (leftmost ち on line 1)
	local crow, ccol = unpack(vim.api.nvim_win_get_cursor(0))
	local want_col = lines[1]:find("ち", 1, true)
	ok(
		crow == 1 and ccol + 1 == want_col,
		("jump ti: cursor on ち (got %d,%d want 1,%d)"):format(crow, ccol, want_col)
	)
else
	ok(false, "jump ti: no state captured")
end

-- language lock through the real loop: prefed C-j becomes the jp marker
-- inside the pattern; ち stays, 梯 (zh) is filtered out
last_state = nil
ok_run, err = run("ti<C-j><cr>")
ok(
	ok_run and err == nil,
	"jump ti+C-j: loop completed without error" .. (err and (": " .. tostring(err)) or "")
)

if last_state and last_state.results then
	local only_ch = #last_state.results > 0
	for _, m in ipairs(last_state.results) do
		if char_at(m) ~= "ち" then
			only_ch = false
		end
	end
	ok(only_ch, "jump ti+C-j: locked to jp, only ち matches")
else
	ok(false, "jump ti+C-j: no state captured")
end

-- language priority through the real loop: the setup-level priority
-- decides which match gets the first label -- ち (ja) or 梯 (zhcn);
-- without one, position order labels the leftmost first.
-- <cr> accepts the default target (jump semantics are untouched by
-- priority); labels stay on the captured state for assertion. The
-- cursor resets between runs so every run starts from the same spot.
-- (<esc> would work once, but flash re-queues the abort escape into
-- the typeahead, silently killing the next prefed jump.)
local function label_of_last(char)
	for _, m in ipairs((last_state and last_state.results) or {}) do
		if char_at(m) == char then
			return m.label
		end
	end
	return nil
end

last_state = nil
fc.setup({ priority = { "ja" } })
ok_run, err = run("ti<cr>")
vim.api.nvim_win_set_cursor(0, { 1, 0 })
ok(
	ok_run and err == nil,
	"priority ja: loop completed without error" .. (err and (": " .. tostring(err)) or "")
)
ok(
	label_of_last("ち") == "a",
	("priority ja: first label on ち (got %s)"):format(tostring(label_of_last("ち")))
)

last_state = nil
fc.setup({ priority = { "zhcn" } })
ok_run, err = run("ti<cr>")
vim.api.nvim_win_set_cursor(0, { 1, 0 })
ok(
	ok_run and err == nil,
	"priority zhcn: loop completed without error" .. (err and (": " .. tostring(err)) or "")
)
ok(
	label_of_last("梯") == "a",
	("priority zhcn: first label on 梯 (got %s)"):format(tostring(label_of_last("梯")))
)

last_state = nil
fc.config.priority = nil
ok_run, err = run("ti<cr>")
vim.api.nvim_win_set_cursor(0, { 1, 0 })
ok(
	ok_run and err == nil,
	"no priority: loop completed without error" .. (err and (": " .. tostring(err)) or "")
)
ok(
	label_of_last("ち") == "a",
	("no priority: position order labels ち first (got %s)"):format(tostring(label_of_last("ち")))
)

-- scrolled window: the exact user-reported regression -- jump must find
-- matches when the visible slice starts below line 1
do
	local slines = {}
	for i = 1, 120 do
		slines[i] = (i % 7 == 0) and ("row " .. i .. " 日本語テスト ち 梯")
			or ("filler " .. i)
	end
	vim.api.nvim_buf_set_lines(0, 0, -1, false, slines)
	lines = slines
	vim.api.nvim_win_set_cursor(0, { 60, 0 })
	vim.cmd("normal! zt")
	last_state = nil
	local ok_s, err_s = run("ti<cr>")
	ok(
		ok_s and err_s == nil,
		"scrolled jump: loop completed without error" .. (err_s and (": " .. tostring(err_s)) or "")
	)
	if last_state and last_state.results then
		ok(#last_state.results > 0, "scrolled jump: matches found below line 1")
		local crow2, ccol2 = unpack(vim.api.nvim_win_get_cursor(0))
		local ch2 = slines[crow2] and slines[crow2]:sub(ccol2 + 1, ccol2 + 3) or ""
		ok(
			ch2 == "ち" or ch2 == "梯",
			"scrolled jump: cursor landed on a matched char (got " .. ch2 .. ")"
		)
	else
		ok(false, "scrolled jump: no state captured")
	end
end

-- nil-opts bounds: flash always passes from/to today, but the
-- matcher's own fallback must still use documented window marks --
-- line("w1") is not a mark (returns 0 on nvim >= 0.10) and made the
-- rust path silently return zero matches with no vim-regex fallback
if not no_rust then
	do
		local matcher = rust.matcher({ zhcn = true, ja = true, ko = true, en = true })
		local fake = {
			pattern = {
				pattern = "ti",
				empty = function()
					return false
				end,
			},
		}
		local ms = matcher(vim.api.nvim_get_current_win(), fake, nil)
		ok(#ms > 0, "nil-opts bounds: visible matches found through the w0/w$ fallback")
		local plausible = true
		for _, m2 in ipairs(ms) do
			local text = (vim.api.nvim_buf_get_lines(0, m2.pos[1] - 1, m2.pos[1], false))[1] or ""
			local b = text:byte(m2.pos[2] + 1)
			plausible = plausible and (b == string.byte("t") or (b and b >= 0x80))
		end
		ok(plausible, "nil-opts bounds: every match sits on a plausible match start")
	end
end

-- server mode: the jumps above ran through the persistent server
-- (warmed before them); parity with the fallback phase is asserted by
-- run.sh
if not no_rust then
	ok(rust.server_ready(), "server mode: session connection open after jumps")
	local addr = rust.server_addr()
	ok(addr ~= nil and vim.uv.fs_stat(addr) ~= nil, "server mode: socket exists")
end

-- 3. Char mode (f/t/F/T) through the real flash char flow: Char.jump
-- driven with the target prefed into the typeahead (flash's getchar
-- consumes nvim_input keys raw, bypassing keymaps -- same technique
-- as fc.jump above). The char wrap is vim-regex in BOTH phases (rust
-- never touches modes.char), so every check is phase-agnostic.
-- Char state is reset between cases: while a char state is visible,
-- the same motion letter means clever-f repeat and reads no new char.
do
	local Char = require("flash.plugins.char")
	-- byte cols (1-based): line 1 中=4 梯=11, line 2 你=4
	local clines = { "aa 中 bb 梯 cc", "xx 你 yy" }
	vim.cmd("enew!")
	vim.api.nvim_buf_set_lines(0, 0, -1, false, clines)
	vim.api.nvim_win_set_cursor(0, { 1, 0 })

	local function char_reset()
		Char.motion = "f"
		Char.char = nil
		Char.current = false
		Char.jump_labels = false
		if Char.state then
			Char.state:hide()
			Char.state = nil
		end
	end

	-- cursor resets between runs so every motion starts from the same
	-- spot (backward cases pass their own start position)
	local function char_jump(motion, prefed, cursor)
		char_reset()
		vim.api.nvim_win_set_cursor(0, cursor or { 1, 0 })
		vim.api.nvim_input(prefed)
		return pcall(Char.jump, motion)
	end

	local function check_landed(label, want_row, want_col, okr, err)
		local r, c = unpack(vim.api.nvim_win_get_cursor(0))
		ok(
			okr and r == want_row and c + 1 == want_col,
			("char %s (got %d,%d want %d,%d%s)"):format(
				label,
				r,
				c + 1,
				want_row,
				want_col,
				not okr and err and (": " .. tostring(err)) or ""
			)
		)
	end

	-- f+t: tyuu (ja) reads 中; 梯 (zhcn ti) is t-initial too but later
	-- on the line -- the leftmost match wins
	local okc, errc = char_jump("f", "t")
	check_landed("f+t: cursor on 中, first t-initial match", 1, 4, okc, errc)

	-- f+v: zhcn flypy singlepin zh -> v reads the same 中
	okc, errc = char_jump("f", "v")
	check_landed("f+v: cursor on 中 (zhcn flypy)", 1, 4, okc, errc)

	-- t+v: native t lands on the char right BEFORE the target
	okc, errc = char_jump("t", "v")
	check_landed("t+v: cursor on char before 中", 1, 3, okc, errc)

	-- F+n: backward from the tail of line 2 onto 你 (ja)
	okc, errc = char_jump("F", "n", { 2, 7 })
	check_landed("F+n: cursor back on 你", 2, 4, okc, errc)

	-- T+t: native T lands on the char right AFTER the target (the
	-- space following 中)
	okc, errc = char_jump("T", "t", { 1, 7 })
	check_landed("T+t: cursor on char after 中", 1, 7, okc, errc)

	-- f+b: plain ascii input stays a literal match
	okc, errc = char_jump("f", "b")
	check_landed("f+b: cursor on literal b", 1, 8, okc, errc)

	-- ";" repeats the last f WITHOUT reading a new char (no prefed
	-- key, straight to the second b from where f+b landed)
	okc, errc = pcall(Char.jump, ";")
	check_landed("; repeat: second b, no new char read", 1, 9, okc, errc)

	-- setup({ motions = { char = false } }) restores native char motions:
	-- no literal z anywhere on the line and no CJK reading consulted,
	-- so the cursor must stay put
	fc.setup({ motions = { char = false } })
	okc, errc = char_jump("f", "z")
	check_landed("motions.char=false: f+z native finds nothing, no move", 1, 1, okc, errc)

	-- re-enable what this section disabled
	fc.setup({ motions = { char = true } })
	ok(fc.config.motions.char == true, "char re-enabled after the disabled check")
end

-- 4. Search mode (/ and ?) through the real cmdline flow: `/` typed
-- via nvim_input opens the cmdline, flash's CmdlineEnter autocmd
-- creates the search state, every CmdlineChanged recompiles the
-- pattern through flash-cjk's mode fn, and typing a label char jumps
-- via flash's own check_jump. The search wrap is vim-regex in BOTH
-- phases (rust never touches modes.search), so every check is
-- phase-agnostic. The cmdline is closed and the module state reset
-- between cases so nothing leaks past this section.
--
-- The main input loop only consumes nvim_input typeahead once this
-- scheduled scenario callback has RETURNED (vim.wait pumps events but
-- never hands queued keys to the cmdline), so the cases run as
-- coroutines driven by a uv timer between cmdline keystrokes --
-- real `/` keys, real autocmds, only the observer is async. The
-- driver owns finish(): it fires once the last case settles.
do
	local Search = require("flash.plugins.search")
	local uv = vim.uv or vim.loop
	local slines = { "aa 中 bb 梯 cc", "xx ち yy" }
	local function buf_reset()
		vim.cmd("enew!")
		vim.api.nvim_buf_set_lines(0, 0, -1, false, slines)
		vim.api.nvim_win_set_cursor(0, { 1, 0 })
	end

	local function match_char(m)
		local line = (vim.api.nvim_buf_get_lines(0, m.pos[1] - 1, m.pos[1], false))[1] or ""
		return line:sub(m.pos[2] + 1, m.pos[2] + 3) -- CJK: 3 bytes
	end

	local function any_cjk(results)
		for _, m in ipairs(results or {}) do
			local ch = match_char(m)
			if ch == "梯" or ch == "ち" then
				return true
			end
		end
		return false
	end

	local function cmdline_open()
		return vim.fn.getcmdtype() ~= ""
	end

	-- suspends the case until pred() holds; the driver resumes with
	-- false once the case deadline passes, so callers fail honestly
	local function yield(pred)
		return (coroutine.yield(pred))
	end

	-- exits any open cmdline FIRST (its CmdlineLeave autocmd still
	-- reads Search.state), then drops the module state
	local function search_reset()
		if cmdline_open() then
			vim.api.nvim_input("<esc>")
		end
		yield(function()
			return not cmdline_open()
		end)
		if Search.state then
			Search.state:hide()
			Search.state = nil
		end
	end

	-- feeds `cmd .. query` into the real cmdline and waits for flash's
	-- state to settle on the full query (waits on the pattern, not on
	-- matches -- literal-only queries legitimately produce none)
	local function cmdline_search(cmd, query)
		vim.api.nvim_input(cmd .. query)
		return yield(function()
			return Search.state ~= nil
				and Search.state.pattern ~= nil
				and Search.state.pattern.pattern == query
		end)
	end

	local cases = {}
	local function add_case(fn)
		cases[#cases + 1] = coroutine.create(fn)
	end

	-- /ti: pinyin 梯 and romaji ち both match through the mix mode,
	-- the compiled pattern keeps the plain-text alternative, and a
	-- real label char jumps the cursor onto the CJK match
	add_case(function()
		buf_reset()
		search_reset()
		local opened = cmdline_search("/", "ti")
		ok(opened, "search /ti: cmdline flow created a flash search state")
		if opened and Search.state.results then
			ok(
				any_cjk(Search.state.results),
				"search /ti: results include CJK (梯/ち) through pinyin+romaji"
			)
			ok(
				Search.state.pattern.search:find("[tT][iI]", 1, true) ~= nil,
				"search /ti: compiled pattern also keeps the literal [tT][iI] alternative"
			)
			local target
			for _, m in ipairs(Search.state.results) do
				if m.label and (match_char(m) == "梯" or match_char(m) == "ち") then
					target = m
					break
				end
			end
			if target then
				local want_r, want_c = target.pos[1], target.pos[2]
				local want_ch = match_char(target)
				-- extends the cmdline by one char naming a label:
				-- flash's check_jump fires, exits the cmdline, jumps
				vim.api.nvim_input(target.label)
				local landed = yield(function()
					local cur = vim.api.nvim_win_get_cursor(0)
					return Search.state == nil and cur[1] == want_r and cur[2] == want_c
				end)
				local cur = vim.api.nvim_win_get_cursor(0)
				ok(
					landed,
					("search /ti: label %s jumped the cursor onto %s (got %d,%d want %d,%d)"):format(
						target.label,
						want_ch,
						cur[1],
						cur[2],
						want_r,
						want_c
					)
				)
			else
				ok(false, "search /ti: no labeled CJK match to jump to")
			end
		elseif opened then
			ok(false, "search /ti: no results on the search state")
		end
	end)

	-- ? runs the same flow backward: same CJK matches, forward=false
	add_case(function()
		buf_reset()
		search_reset()
		local opened = cmdline_search("?", "ti")
		ok(opened, "search ?ti: cmdline flow created a flash search state")
		if opened and Search.state.results then
			ok(
				Search.state.opts.search.forward == false,
				"search ?ti: state marks the search backward (forward=false)"
			)
			ok(any_cjk(Search.state.results), "search ?ti: results include CJK (梯/ち)")
		elseif opened then
			ok(false, "search ?ti: no results on the search state")
		end
	end)

	-- metacharacter queries pass through verbatim: `.*` must reach
	-- flash as the plain vim regex it was typed as, not a CJK class
	add_case(function()
		buf_reset()
		search_reset()
		local opened = cmdline_search("/", ".*")
		ok(opened, "search /.*: cmdline flow reached the pattern")
		if opened then
			ok(
				Search.state.pattern.search == ".*",
				("search /.*: pattern passed through verbatim (got %s)"):format(
					tostring(Search.state.pattern.search)
				)
			)
		end
	end)

	-- gate: motions.search=false leaves flash's search mode untouched
	-- -- the pattern mode stays flash's own "search" string and /ti is
	-- literal-only (no CJK results; this buffer has no literal "ti")
	add_case(function()
		fc.setup({ motions = { search = false } })
		buf_reset()
		search_reset()
		local opened = cmdline_search("/", "ti")
		ok(opened, "search gate: cmdline flow created a flash search state")
		if opened then
			ok(
				type(Search.state.pattern.mode) == "string",
				"search gate: pattern mode untouched (flash's own string)"
			)
			ok(
				not any_cjk(Search.state.results),
				"search gate: /ti literal-only with motions.search=false (no CJK results)"
			)
		end
		search_reset()

		-- re-enable what this section disabled
		fc.setup({ motions = { search = true } })
		ok(fc.config.motions.search == true, "search re-enabled after the disabled check")
	end)

	-- trailer: never leave the cmdline open past this section, so no
	-- cmdline state leaks into anything that runs later
	add_case(function()
		-- (a blocking getchar drain is off-limits here: it would stall
		-- the driver mid-case, past even its deadline)
		search_reset()
	end)

	-- one resume per tick: start the case (pred == nil), or resume it
	-- with the pred's verdict -- false once the per-case deadline
	-- passes, so timeouts fail their check instead of hanging
	local timer = assert(uv.new_timer())
	local idx, pred, deadline = 1, nil, nil
	local CASE_MS, SECTION_MS = 5000, 60000
	local section_deadline = uv.now() + SECTION_MS
	-- ticks queued while a case body pumps the loop must not resume
	-- the still-running coroutine ("cannot resume running coroutine")
	local ticking = false
	local function stop()
		timer:stop()
		timer:close()
		finish()
	end
	local function step()
		if uv.now() > section_deadline then
			ok(false, "search section: global timeout")
			return stop()
		end
		local co = cases[idx]
		if not co then
			return stop()
		end
		if coroutine.status(co) == "dead" then
			idx, pred = idx + 1, nil
			return
		end
		local verdict = pred and pred()
		if pred and not verdict and uv.now() <= deadline then
			return -- still waiting on the current pred
		end
		local ran, next_pred = coroutine.resume(co, pred and verdict or nil)
		deadline = uv.now() + CASE_MS
		if not ran then
			ok(false, "search case crashed: " .. tostring(next_pred))
			idx, pred = idx + 1, nil
			return
		end
		if coroutine.status(co) == "dead" then
			idx, pred = idx + 1, nil
		else
			pred = next_pred
		end
	end
	timer:start(
		10,
		10,
		vim.schedule_wrap(function()
			if ticking then
				return
			end
			ticking = true
			local ran, err = pcall(step)
			ticking = false
			if not ran then
				ok(false, "search case crashed: " .. tostring(err))
				idx, pred = idx + 1, nil
			end
		end)
	)
end
