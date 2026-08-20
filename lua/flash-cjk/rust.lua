-- Rust matcher bridge: talks to a persistent flash-cjk-search server
-- over a Unix domain socket when possible (Unix only, zero config),
-- falls back to spawning the binary per keystroke, and falls back
-- further to flash's vim-regex searcher when the binary is
-- unavailable or keeps failing (circuit breaker).
--
-- Server lifecycle (connection-based, see rust/crates/flash-cjk-search/
-- src/serve.rs): this instance registers by holding one idle session
-- connection open; the server exits once no client has held a session
-- for the grace period, so the last Neovim instance out takes the
-- server with it. On VimLeavePre we send {"cmd":"bye"} and close the
-- session as a best-effort fast path.

local M = {}

local uv = vim.uv

local bin ---@type string?
local disabled = false -- circuit breaker: set after repeated failures

local FAIL_LIMIT = 3
local fails = 0

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

-- ---------------------------------------------------------------------------
-- persistent-server transport

-- Protocol version baked into the socket name: a server speaking an
-- incompatible envelope gets a different socket instead of a broken
-- conversation.
local PROTO = 1
local REQ_TIMEOUT = 200 -- ms per request before this keystroke falls back
local WARM_BUDGET = 2000 -- ms of async probing after spawning the server
local PROBE_INTERVAL = 50 -- ms between readiness probes

---@class flashcjk.server
local server = {
	path = nil, ---@type string?
	warming = false, -- warmup pass in flight
	spawning = false, -- spawn+probe pass in flight
	probing = false, -- restart probe scheduled
	off = false, -- transport disabled for this session
	fails = 0, -- transport-level failures (server -> spawn fallback)
	session = nil, ---@type uv_pipe? held-open session connection
	timer = nil, ---@type uv_timer? in-flight spawn probe timer
	timeout = REQ_TIMEOUT,
	bye_installed = false,
}

---Resolves the shared per-user socket path (the single source of
---truth on the Lua side) and creates its directory.
---@return string? path
local function socket_path()
	-- os.getenv, not vim.env: socket_path can run inside libuv
	-- callbacks (probe ticks), where the vimscript-backed vim.env
	-- raises E5560; os.getenv is a plain C call that stays in sync
	-- with vim.env writes (they call setenv).
	local base = os.getenv("XDG_RUNTIME_DIR")
	if not base or base == "" then
		base = os.getenv("TMPDIR")
	end
	if not base or base == "" then
		base = "/tmp"
	end
	base = vim.fs.normalize(base)
	local dir = ("%s/flash-cjk-%d"):format(base, uv.getuid())
	pcall(vim.fn.mkdir, base, "p")
	pcall(uv.fs_mkdir, dir, 448) -- 0700; EEXIST is fine
	pcall(uv.fs_chmod, dir, 448) -- enforce even when it pre-existed
	local sock = ("%s/server-v%d.sock"):format(dir, PROTO)
	if #sock > 100 then
		return nil -- sun_path cap (104 on macOS, 108 on Linux): can never bind
	end
	return sock
 end

local schedule_restart_probe -- forward declaration (session EOF hook)

local function is_unix()
	return vim.fn.has("unix") == 1
end

local function close_pipe(p)
	if p and not p:is_closing() then
		p:close()
	end
end

---Drops the registration: closes the session connection. The server
---sees EOF and deregisters us immediately (same as process death).
local function drop_session()
	local s = server.session
	server.session = nil
	if s then
		pcall(function()
			s:read_stop()
		end)
		close_pipe(s)
	end
end

---Installs the VimLeavePre fast path: say bye, then close the session
---(the close alone already deregisters us — the server sees EOF).
local function install_bye()
	if server.bye_installed then
		return
	end
	server.bye_installed = true
	-- the session can open inside a libuv callback (fast event
	-- context); autocmds must be created from the main loop
	vim.schedule(function()
		vim.api.nvim_create_autocmd("VimLeavePre", {
			once = true,
			callback = function()
				local s = server.session
				server.session = nil
				if not s then
					return
				end
				local sent = false
				s:write(('{"cmd":"bye","pid":%d}\n'):format(uv.os_getpid()), function()
					sent = true
				end)
				vim.wait(100, function()
					return sent
				end, 1) -- best-effort flush; EOF works even without it
				pcall(function()
					s:read_stop()
				end)
				close_pipe(s)
			end,
		})
	end)
end

---Opens the session connection: connect, hello, wait for the ok. On
---success the pipe is kept open (it IS the registration) and assigned
---to server.session; any earlier session is dropped first.
---@param cb fun(ok: boolean, err?: string) called once
local function open_session(cb)
	local path = server.path or socket_path()
	if not path then
		cb(false, "socket path too long")
		return
	end
	server.path = path
	local done = false
	local pipe = uv.new_pipe()
	local function finish(ok, err)
		if done then
			return
		end
		done = true
		if ok then
			if server.session ~= pipe then
				drop_session()
			end
			server.session = pipe
			install_bye()
			cb(true)
		else
			close_pipe(pipe)
			cb(false, err)
		end
	end
	pipe:connect(path, function(err)
		if err then
			finish(false, err)
			return
		end
		pipe:read_start(function(rerr, data)
			if rerr or data == nil then
				-- EOF/error. Before the ok: the server never answered.
				-- After it (done): the server died under us — drop the
				-- registration so the next request falls back, and probe
				-- for a replacement asynchronously.
				if done and server.session == pipe then
					drop_session()
					schedule_restart_probe()
				end
				finish(false, rerr or "eof")
				return
			end
			finish(true)
		end)
		pipe:write(('{"cmd":"hello","pid":%d}\n'):format(uv.os_getpid()), function(werr)
			if werr then
				finish(false, werr)
			end
		end)
	end)
end

---Spawns the server detached (its own session/process group) and
---probes the socket until it answers, all asynchronous.
---@param cb fun(ok: boolean) called once
local function spawn_and_probe(cb)
	if server.spawning then
		return
	end
	server.spawning = true
	local fired = false
	local function finish(ok)
		if fired then
			return
		end
		fired = true
		server.spawning = false
		cb(ok)
	end
	local path = server.path or socket_path()
	if not path then
		finish(false)
		return
	end
	server.path = path
	-- connect failed but the socket file remains: a server was killed
	-- without cleanup. It would block the new bind, so reclaim it.
	local stat = uv.fs_stat(path)
	if stat then
		pcall(uv.fs_unlink, path)
	end
	server.proc = uv.spawn(find_bin(), {
		args = { "serve", "--socket", path },
		-- own session/process group: survives nvim, ignores terminal
		-- signals; silent by default
		detach = true,
		stdio = { nil, nil, nil },
	}, function()
		server.proc = nil
	end)
	if not server.proc then
		finish(false)
		return
	end
	local deadline = uv.now() + WARM_BUDGET
	local timer = uv.new_timer()
	-- tracked so reset_server_for_test can cancel an in-flight probe:
	-- its deadline callback would otherwise nil server.path and wreck
	-- whatever probe replaced it
	server.timer = timer
	local function kill_timer()
		if timer ~= nil then
			pcall(function()
				timer:stop()
				timer:close()
			end)
			timer = nil
			server.timer = nil
		end
	end
	timer:start(PROBE_INTERVAL, PROBE_INTERVAL, function()
		if server.session or server.off then
			kill_timer()
			finish(server.session ~= nil)
		elseif uv.now() >= deadline then
			kill_timer()
			finish(false)
		else
			open_session(function(ok)
				if ok then
					kill_timer()
					finish(true)
				end
			end)
		end
	end)
end

---One-shot async recovery: reconnect to a live server if one exists,
---else spawn a replacement. Failing both disables the transport for
---this session (the spawn transport keeps serving; its own circuit
---breaker is unchanged).
function schedule_restart_probe()
	if server.probing or server.spawning or server.off or not is_unix() then
		return
	end
	if server.session or disabled or not M.available() then
		return
	end
	server.probing = true
	vim.defer_fn(function()
		server.probing = false
		if server.off or server.session then
			return
		end
		open_session(function(ok)
			if not ok then
				spawn_and_probe(function(ok2)
					if not ok2 then
						server.off = true
					end
				end)
			end
		end)
	end, 10)
end

---Non-blocking warm-up, called from build_opts on first jump: reuse a
---live server if one answers, otherwise spawn one and probe for up to
---WARM_BUDGET. Until the session is confirmed, keystrokes use the
---spawn transport (correctness first).
function M.warmup()
	if not is_unix() or disabled or server.off or server.warming or server.session then
		return
	end
	if not M.available() then
		return
	end
	server.warming = true
	open_session(function(ok)
		if ok then
			server.warming = false
			return
		end
		spawn_and_probe(function(ok2)
			server.warming = false
			if not ok2 then
				-- nothing to warm; retry on the next jump
				server.path = nil
			end
		end)
	end)
end

---Sends one NDJSON line and waits (pumping the loop; the matcher is a
---synchronous call site — no reentry) for the one-line response.
---@param payload string JSON request without the newline
---@param timeout number ms
---@return string? line response line without the newline
---@return string? err nil, "timeout", or a uv error name
local function request(payload, timeout)
	local pipe = uv.new_pipe()
	local st = { done = false, buf = "", line = nil, err = nil, closed = false }
	local function tear(err)
		if st.done then
			return
		end
		st.done = true
		st.err = err
	end
	pipe:connect(server.path, function(err)
		if st.closed then
			return
		end
		if err then
			tear(err)
			return
		end
		pipe:read_start(function(rerr, chunk)
			if st.done then
				return
			end
			if rerr then
				tear(rerr)
			elseif chunk then
				st.buf = st.buf .. chunk
				local nl = st.buf:find("\n", 1, true)
				if nl then
					st.line = st.buf:sub(1, nl - 1)
					st.done = true
				end
			else -- EOF before a full response line
				tear("eof")
			end
		end)
		pipe:write(payload .. "\n", function(werr)
			if werr then
				tear(werr)
			end
		end)
	end)
	if not vim.wait(timeout, function()
		return st.done
	end, 1) then
		tear("timeout")
	end
	st.closed = true
	pcall(function()
		pipe:read_stop()
	end)
	close_pipe(pipe)
	return st.line, st.err
end

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

local function encode_req(pattern, lines, langs)
	return vim.json.encode({
		pattern = pattern,
		lines = lines,
		pid = uv.os_getpid(),
		langs = {
			zhcn = langs.zhcn and true or false,
			ja = langs.ja and true or false,
			ko = langs.ko and true or false,
			en = langs.en and true or false,
			alpha_mixing = langs.alpha_mixing ~= false,
		},
	})
end

local function valid_response(resp)
	return type(resp) == "table" and type(resp.matches) == "table"
end

---Runs the binary for one keystroke through the per-keystroke spawn
---transport (the original path; also the fallback for the server
---transport and the transport used on non-Unix platforms).
---@param pattern string raw pattern (lock markers included)
---@param lines string[] visible buffer lines
---@param langs table language flags
---@return table? response { matches = { {line,col,end_col,len}... }, predictions = { string... }, pred_langs = { { string... }... } }
function M.search_spawn(pattern, lines, langs)
	local path = find_bin()
	local req = encode_req(pattern, lines, langs)
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
	if not okd or not valid_response(resp) then
		fails = fails + 1
		if fails >= FAIL_LIMIT then
			disabled = true
		end
		return nil
	end
	fails = 0
	return resp
end

---Runs the binary for one keystroke: persistent server transport when
---the session is confirmed open, otherwise the spawn transport. Any
---transport failure falls back to the spawn transport for this
---keystroke and counts toward disabling the server transport only;
---the spawn path keeps its own circuit breaker.
---@param pattern string raw pattern (lock markers included)
---@param lines string[] visible buffer lines
---@param langs table language flags
---@return table? response
function M.search(pattern, lines, langs)
	if server.session and not disabled and is_unix() then
		local line, err = request(encode_req(pattern, lines, langs), server.timeout)
		local okd, resp = pcall(vim.json.decode, line or "")
		if okd and valid_response(resp) then
			server.fails = 0
			return resp
		end
		-- the request itself failed (timeout, refused, EOF): drop the
		-- registration and probe for a replacement asynchronously
		drop_session()
		server.fails = server.fails + 1
		if server.fails >= FAIL_LIMIT then
			server.off = true
		else
			schedule_restart_probe()
		end
	end
	return M.search_spawn(pattern, lines, langs)
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

-- ---------------------------------------------------------------------------
-- introspection and test hooks

---@return string? path the resolved socket path (Unix only)
function M.server_addr()
	if not is_unix() then
		return nil
	end
	return server.path or socket_path()
end

---@return boolean true when the session connection is confirmed open
function M.server_ready()
	return server.session ~= nil
end

---Test hooks: trip / clear the circuit breaker.
function M.disable_for_test()
	disabled = true
end

function M.enable_for_test()
	disabled = false
	fails = 0
end

---Test hooks for the server transport: shrink the per-request timeout
---and reset the transport state (closing any session without bye, like
---a killed instance would).
function M.set_server_timeout_for_test(ms)
	server.timeout = ms
end

function M.reset_server_for_test()
	drop_session()
	-- cancel any in-flight spawn probe: reset must leave no timer
	-- whose failure callback can still clear server.path afterwards
	if server.timer ~= nil then
		pcall(function()
			server.timer:stop()
			server.timer:close()
		end)
		server.timer = nil
	end
	server.warming = false
	server.spawning = false
	server.probing = false
	server.off = false
	server.fails = 0
	server.path = socket_path()
end

return M
