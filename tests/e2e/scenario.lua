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
end

local function finish()
  out:write(("SUMMARY %d %d\n"):format(passed, failed))
  out:close()
  vim.cmd("qa!")
end

-- 1. lazy.nvim installed and can load the spec.
vim.cmd("Lazy load flash-cjk.nvim")
local fc = require("flash-cjk")
local cfg = require("flash-cjk.config")
ok(type(fc.jump) == "function" and type(fc.remote) == "function", "lazy load: flash-cjk module resolves")

ok(
    fc.config.languages.zhcn.scheme == "xiaohe"
      and fc.config.languages.ja.scheme == "roma"
      and fc.config.languages.ko.scheme == "roma",
    "opts: lazy opts normalized into schemes"
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
-- tests/run.lua). last_state captures the flash state via a labeler
-- wrapper that chains into flash-cjk's own labeler, so behavior under
-- test is exactly build_opts' default.
local last_state
local keys = cfg.force_keys(fc.config.languages)

local function jump_capture(opts)
  opts = opts or {}
  opts.labeler = function(_, state)
    last_state = state
    require("flash-cjk.labeler").new(state, fc.resolve_langs(nil, opts), keys, cfg.effective_priority(opts)):update()
  end
  return fc.jump(nil, opts)
end

local function run(prefed, opts)
  vim.api.nvim_input(prefed)
  local ok_run, err = pcall(jump_capture, opts or {})
  return ok_run, err
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
ok(ok_run and err == nil, "jump ti: loop completed without error" .. (err and (": " .. tostring(err)) or ""))

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
  ok(crow == 1 and ccol + 1 == want_col, ("jump ti: cursor on ち (got %d,%d want 1,%d)"):format(crow, ccol, want_col))
else
  ok(false, "jump ti: no state captured")
end

-- language lock through the real loop: prefed C-j becomes the jp marker
-- inside the pattern; ち stays, 梯 (zh) is filtered out
last_state = nil
ok_run, err = run("ti<C-j><cr>")
ok(ok_run and err == nil, "jump ti+C-j: loop completed without error" .. (err and (": " .. tostring(err)) or ""))

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

-- language priority through the real loop: the per-jump priority
-- override decides which match gets the first label -- ち (ja) or 梯
-- (zhcn); without one, position order labels the leftmost first.
-- <cr> accepts the default target (jump semantics are untouched by
-- priority); labels stay on the captured state for assertion. The
-- cursor resets between runs so every run starts from the same spot.
-- (<esc> would work once, but flash re-queues the abort escape into
-- the typeahead, silently killing the next prefed jump.)
local function label_of_last(char)
  for _, m in ipairs(last_state.results or {}) do
    if char_at(m) == char then
      return m.label
    end
  end
  return nil
end

last_state = nil
ok_run, err = run("ti<cr>", { priority = { "ja" } })
vim.api.nvim_win_set_cursor(0, { 1, 0 })
ok(ok_run and err == nil, "priority ja: loop completed without error" .. (err and (": " .. tostring(err)) or ""))
ok(label_of_last("ち") == "a", ("priority ja: first label on ち (got %s)"):format(tostring(label_of_last("ち"))))

last_state = nil
ok_run, err = run("ti<cr>", { priority = { "zhcn" } })
vim.api.nvim_win_set_cursor(0, { 1, 0 })
ok(ok_run and err == nil, "priority zhcn: loop completed without error" .. (err and (": " .. tostring(err)) or ""))
ok(label_of_last("梯") == "a", ("priority zhcn: first label on 梯 (got %s)"):format(tostring(label_of_last("梯"))))

last_state = nil
ok_run, err = run("ti<cr>", {})
vim.api.nvim_win_set_cursor(0, { 1, 0 })
ok(ok_run and err == nil, "no priority: loop completed without error" .. (err and (": " .. tostring(err)) or ""))
ok(label_of_last("ち") == "a", ("no priority: position order labels ち first (got %s)"):format(tostring(label_of_last("ち"))))

-- scrolled window: the exact user-reported regression -- jump must find
-- matches when the visible slice starts below line 1
do
  local slines = {}
  for i = 1, 120 do
    slines[i] = (i % 7 == 0) and ("row " .. i .. " 日本語テスト ち 梯") or ("filler " .. i)
  end
  vim.api.nvim_buf_set_lines(0, 0, -1, false, slines)
  lines = slines
  vim.api.nvim_win_set_cursor(0, { 60, 0 })
  vim.cmd("normal! zt")
  last_state = nil
  local ok_s, err_s = run("ti<cr>")
  ok(ok_s and err_s == nil, "scrolled jump: loop completed without error" .. (err_s and (": " .. tostring(err_s)) or ""))
  if last_state and last_state.results then
    ok(#last_state.results > 0, "scrolled jump: matches found below line 1")
    local crow2, ccol2 = unpack(vim.api.nvim_win_get_cursor(0))
    local ch2 = slines[crow2] and slines[crow2]:sub(ccol2 + 1, ccol2 + 3) or ""
    ok(ch2 == "ち" or ch2 == "梯", "scrolled jump: cursor landed on a matched char (got " .. ch2 .. ")")
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

finish()
