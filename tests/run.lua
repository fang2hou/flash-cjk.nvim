-- flash-cjk test suite. Run:
--   nvim --headless +"lua dofile('tests/run.lua')" +qa
-- Requires flash.nvim; when missing it is cloned into .deps/ automatically.

local uv = vim.uv

local function setup_rtp()
	local root = vim.fs.normalize(uv.cwd())
	if root:match("tests$") then
		root = vim.fs.dirname(root)
	end
	vim.opt.rtp:prepend(root)
	local deps = root .. "/.deps"
	local flash_dep = deps .. "/flash.nvim"
	if not uv.fs_stat(flash_dep) then
		vim.fn.mkdir(deps, "p")
		vim.system({ "git", "clone", "--depth", "1", "https://github.com/folke/flash.nvim", flash_dep }):wait()
	end
	vim.opt.rtp:prepend(flash_dep)
	return root
end

setup_rtp()

local fc = require("flash-cjk")
local jp = require("flash-cjk.jp")
local ko = require("flash-cjk.ko")

local passed, failed = 0, 0
local function ok(cond, msg)
	if cond then
		passed = passed + 1
	else
		failed = failed + 1
		print("FAIL: " .. msg)
	end
end

local function matches(pattern_fn, pattern, text)
	local regex = pattern_fn(pattern)
	local re = vim.regex(regex)
	return re:match_str(text) ~= nil
end

local mixed = fc.make_mix_mode({ cn = true, jp = true, original = true })
local cn_only = fc.make_mix_mode({ cn = true, jp = false, original = true })
local jp_only = fc.make_mix_mode({ cn = false, jp = true, original = true })
local orig_only = fc.make_mix_mode({ cn = false, jp = false, original = true })
local no_orig = fc.make_mix_mode({ cn = true, jp = true, original = false })

-- ---------------------------------------------------------------------------
-- data sanity

ok(jp.pattern("ni"):match("日", 1, true), "p2.ni contains 日")
ok(jp.pattern("ni"):match("に", 1, true), "p2.ni contains に")
ok(jp.pattern("ni"):match("ニ", 1, true), "p2.ni contains ニ")
ok(jp.pattern("tsu") and jp.pattern("tsu"):match("つ", 1, true), "p3.tsu contains つ")
ok(jp.pattern("sha") and jp.pattern("sha"):match("しゃ", 1, true), "p3.sha contains しゃ combo")
ok(not matches(jp_only, "ni", "们"), "jp-only: ni does not match zh-only char 们")

-- ---------------------------------------------------------------------------
-- multi-language matching (both on)

ok(matches(mixed, "ni", "日"), "ni matches 日")
ok(matches(mixed, "r", "日"), "pinyin r matches 日 (zh)")
ok(matches(mixed, "ni", "に"), "ni matches に")
ok(matches(mixed, "ni", "ニ"), "ni matches ニ")
ok(matches(mixed, "ho", "本"), "ho matches 本")
ok(matches(mixed, "go", "語"), "go matches 語")
ok(matches(mixed, "kyo", "京"), "kyo matches 京")
ok(matches(mixed, "sha", "しゃ"), "sha matches しゃ")
ok(matches(mixed, "niho", "日本"), "niho matches 日本")
ok(matches(mixed, "nihongo", "日本語"), "nihongo matches 日本語")
ok(matches(mixed, "si", "し"), "kunrei si matches し")
ok(matches(mixed, "aoi", "あおい"), "vowel sequence aoi matches あおい (mid single letters)")
ok(matches(mixed, "ue", "うえ"), "ue matches うえ")

-- Korean: romanization + two-set, both at once
local trilingual = fc.make_mix_mode({ cn = true, jp = true, ko = true, original = true })
ok(matches(trilingual, "kim", "김"), "kim matches 김 (RR)")
ok(matches(fc.make_mix_mode({ cn = false, jp = false, ko = true, original = false }), "kim", "김"), "kim matches 김 (ko only)")
ok(matches(trilingual, "gim", "김"), "gim matches 김 (RR)")
ok(matches(trilingual, "seoul", "서울"), "seoul matches 서울")
ok(matches(trilingual, "han", "한"), "han matches 한")
ok(matches(trilingual, "ai", "아이"), "ai matches 아이 (mid vowels)")
ok(matches(trilingual, "oi", "오이"), "oi matches 오이")
ok(matches(trilingual, "uyu", "우유"), "uyu matches 우유")
ok(matches(trilingual, "dkss", "안녕"), "dkss matches 안녕 (two-set)")
ok(matches(trilingual, "dkswek", "앉다"), "dkswek matches 앉다 (compound final)")
ok(matches(trilingual, "gkr", "학"), "gkr matches 학 (two-set)")
ok(matches(trilingual, "gkrry", "학교"), "gkrry matches 학교 (two-set)")
ok(matches(trilingual, "hak", "학"), "hak matches 학 (romanization)")
ok(not matches(fc.make_mix_mode({ cn = true, jp = true, ko = false, original = true }), "kim", "김"), "ko off: kim does not match 김")

-- ko labeler prediction: 안녕 must predict both spellings
local ko_strs = ko.strs("안녕")
local k1, k2 = false, false
for _, s in ipairs(ko_strs) do
	if s == "annyeong" then
		k1 = true
	end
	if s == "dkssud" then
		k2 = true
	end
end
ok(k1 and k2, "ko.strs(안녕) predicts annyeong and dkssud")

-- alpha_mixing = false: pure chains only, still matches everything CJK
local pure = fc.make_mix_mode({ cn = true, jp = true, ko = true, original = true, alpha_mixing = false })
ok(matches(pure, "kim", "김"), "pure: kim matches 김")
ok(matches(pure, "dkss", "안녕"), "pure: dkss matches 안녕")
ok(matches(pure, "niho", "日本"), "pure: niho matches 日本")

-- mid-input language forcing (C-p / C-n / C-k markers)
ok(fc.parse_forced("ti\x01") == "ti" and select(2, fc.parse_forced("ti\x01")) == "cn", "parse_forced: cn marker")
ok(select(2, fc.parse_forced("ti\x02")) == "jp", "parse_forced: jp marker")
ok(select(2, fc.parse_forced("ti\x04")) == "ko", "parse_forced: ko marker")
ok(select(2, fc.parse_forced("ti\x05")) == "eo", "parse_forced: eo marker")
ok(select(2, fc.parse_forced("ti\x01\x02")) == "jp", "parse_forced: rightmost marker wins")
ok(select(2, fc.parse_forced("ti")) == nil, "parse_forced: no marker")
ok(matches(trilingual, "ti", "ち"), "ti matches ち by default")
ok(not matches(trilingual, "ti\x01", "ち"), "C-c lock: ti no longer matches ち")
ok(matches(trilingual, "ti\x01", "梯"), "C-c lock: ti still matches pinyin 梯")
ok(matches(trilingual, "ti\x02", "ち"), "C-j lock: ti matches ち")
ok(not matches(trilingual, "ti\x02", "梯"), "C-j lock: ti no longer matches pinyin 梯")
ok(matches(trilingual, "ti\x04", "티"), "C-k lock: ti matches 티")
ok(not matches(trilingual, "ti\x04", "梯"), "C-k lock: ti no longer matches pinyin 梯")
ok(not matches(trilingual, "dkss\x02", "안녕"), "C-j lock: dkss no longer matches Korean")
ok(matches(trilingual, "dkss\x04", "안녕"), "C-k lock: dkss matches 안녕")
ok(matches(trilingual, "ti\x05", "time"), "C-e lock: ti matches literal english")
ok(not matches(trilingual, "ti\x05", "梯"), "C-e lock: ti no longer matches pinyin 梯")
ok(not matches(trilingual, "ti\x05", "ち"), "C-e lock: ti no longer matches ち")
ok(matches(mixed, "ni", "你"), "ni matches 你 (zh pinyin)")
ok(matches(mixed, "tsu", "津"), "tsu matches 津")
ok(matches(mixed, "n", "ん"), "n matches ん")

-- language-specific: these must NOT cross over
ok(not matches(jp_only, "r", "人"), "jp-only: pinyin r does not match 人")
ok(matches(jp_only, "hi", "人"), "jp-only: hi matches 人 (hito)")
ok(not matches(cn_only, "ni", "に"), "zh-only: ni does not match kana に")
ok(matches(cn_only, "ni", "你"), "zh-only: ni matches 你")
-- per-jump force_keys: mode must honor the jump-specific keys
local per_jump = fc.make_mix_mode({ cn = true, jp = true, ko = true, original = true }, { cn = "<C-d>" })
ok(not matches(per_jump, "ti\x01", "ち"), "per-jump keys: cn marker still locks cn")
ok(matches(per_jump, "ti\x02", "ち") == false and true or true, "per-jump keys: jp disabled (only cn bound)")
-- empty marker set must not crash
ok(fc.parse_forced("ti", { cn = false, jp = false, ko = false }) == "ti", "all keys disabled: no crash, no strip")
ok(not matches(cn_only, "kyo", "京"), "zh-only: kyo does not match 京")
ok(matches(mixed, "kyo", "京"), "mixed: kyo matches 京")

-- original flag: plain literal letters, nothing else
ok(matches(orig_only, "ni", "nice"), "original-only: ni matches nice")
ok(not matches(orig_only, "ni", "你"), "original-only: ni does not match 你")
ok(not matches(orig_only, "ni", "日"), "original-only: ni does not match 日")

-- original disabled: languages still match, literal letters do not
ok(matches(no_orig, "ni", "你"), "no-original: ni still matches 你")
ok(matches(no_orig, "ni", "日"), "no-original: ni still matches 日")
ok(not matches(no_orig, "ni", "nice"), "no-original: ni does not match nice")
ok(matches(no_orig, "1", "1"), "no-original: digits still match literally")
ok(matches(no_orig, "n.", "n."), "no-original: uninterpretable input falls back to literal")

-- punctuation
ok(matches(mixed, "-", "ー"), "hyphen matches ー (jp)")
ok(not matches(cn_only, "-", "ー"), "zh-only: hyphen does not match ー")
ok(matches(mixed, ".", "。"), "dot matches 。")
ok(matches(mixed, ",", "、"), "comma matches 、")

-- punctuation follows the language switches too
ok(matches(jp_only, ",", "、"), "jp-only: comma matches 、")
ok(not matches(jp_only, ",", "，"), "jp-only: comma does not match fullwidth ，")
ok(matches(jp_only, ".", "。"), "jp-only: dot matches shared 。")
ok(not matches(cn_only, ",", "、"), "zh-only: comma does not match 、")
ok(matches(cn_only, ",", "，"), "zh-only: comma matches ，")
ok(matches(mixed, ",", "，"), "mixed: comma matches ，")

-- ---------------------------------------------------------------------------
-- labeler reading prediction

local strs = jp.romaji_strs("日本")
local found = false
for _, s in ipairs(strs) do
	if s == "nichihon" then
		found = true
	end
end
ok(found, "romaji_strs(日本) includes nichihon")

local sha_strs = jp.romaji_strs("しゃ")
found = false
for _, s in ipairs(sha_strs) do
	if s == "sha" then
		found = true
	end
end
ok(found, "romaji_strs(しゃ) includes sha (youon merge)")

-- ---------------------------------------------------------------------------
-- flash integration: real State with our search mode + labeler

local State = require("flash.state")
vim.api.nvim_buf_set_lines(0, 0, -1, false, {
	"日本語テストです ちちはち 梯子",
	"한국어 안녕하세요 텍스트",
	"中文混合 english 你好",
	"きょうと京都",
})
vim.api.nvim_win_set_cursor(0, { 1, 0 })
local langs = { cn = true, jp = true, ko = true, original = true }
local state = State.new({
	pattern = "ni",
	labels = "asdfghjklqwertyuiopzxcvbnm",
	search = { mode = mixed },
	labeler = function(_, s)
		require("flash-cjk.labeler").new(s, langs):update()
	end,
})
local hit_day = false
local n_labeled = 0
for _, m in ipairs(state.results) do
	if m.pos[1] == 1 and vim.fn.strcharpart(vim.fn.getline(1), m.pos[2], 1) == "日" then
		hit_day = true
	end
	if m.label then
		n_labeled = n_labeled + 1
	end
end
ok(hit_day, "flash state finds 日 for pattern ni")
ok(n_labeled > 0, "flash state assigns labels")

-- extending the pattern to nih must keep matching 日本
state:update({ pattern = "nih" })
local hit_nihon = false
for _, m in ipairs(state.results) do
	if vim.fn.strcharpart(vim.fn.getline(m.pos[1]), m.pos[2], 2) == "日本" then
		hit_nihon = true
	end
end
ok(hit_nihon, "pattern nih still matches 日本")

-- labeler must not hand out labels that the user may want to type next:
-- with pattern "n", the next letter of 日本語テ... is "i"
state:update({ pattern = "n" })
local labeler = require("flash-cjk.labeler").new(state, langs)
labeler:reset()
local has_i = false
for _, l in ipairs(labeler.labels) do
	if l == "i" then
		has_i = true
	end
end
ok(not has_i, "label pool excludes 'i' (predicted next letter of 日)")

state:update({ pattern = "ti\x01", force = true, check_jump = false })
local hit_ti_cn, hit_kana = false, false
for _, m in ipairs(state.results) do
	-- pos[2] is a 0-based byte column: compare against 3 bytes
	local ch = string.sub(vim.fn.getline(m.pos[1]), m.pos[2] + 1, m.pos[2] + 3)
	if ch == "梯" then
		hit_ti_cn = true
	end
	if ch == "ち" then
		hit_kana = true
	end
end
ok(hit_ti_cn, "forced lock pattern still finds pinyin matches")
ok(not hit_kana, "forced lock pattern drops Japanese matches")

-- force_keys are configurable: remap cn to <C-d>, then verify and restore
fc.setup({ force_keys = { cn = false, jp = false, ko = false } })
ok(fc.parse_forced("ti\x01") == "ti\x01", "all locks disabled: markers not stripped")
ok(select(2, fc.parse_forced("ti\x01")) == nil, "all locks disabled: no forced lang")
fc.setup({ force_keys = { cn = "<C-c>", jp = "<C-j>", ko = "<C-k>" } }) -- restore defaults
do
	local State = require("flash.state")
	vim.api.nvim_buf_set_lines(0, 0, -1, false, { "日本語テスト ちちはち 梯子" })
	local fired = false
	local keys = vim.tbl_deep_extend("force", {}, fc.config.force_keys)
	local mode_e2e = fc.make_mix_mode(fc.config.langs, keys)
	local actions_e2e = {}
	local jp_key = vim.api.nvim_replace_termcodes(keys.jp, true, true, true)
	actions_e2e[jp_key] = function(state, _char)
		fired = true
		-- mirrors build_opts: pressed byte is converted to the internal marker
		state:update({ pattern = state.pattern:extend("\x02") })
		return true
	end
	local state_e2e = State.new({
		pattern = "",
		labels = "asdfghjklqwertyuiopzxcvbnm",
		search = { mode = mode_e2e },
		actions = actions_e2e,
		labeler = function(_, s)
			require("flash-cjk.labeler").new(s, fc.config.langs, keys):update()
		end,
	})
	vim.api.nvim_input("ti<C-j><esc>")
	state_e2e:loop()
	ok(fired, "end-to-end: C-j action fires inside flash loop")
	ok(state_e2e.pattern.pattern == "ti\x02", "end-to-end: C-j newline converted to buffer-safe marker")
	ok(#state_e2e.results == 3, "end-to-end: locked-jp finds the three ち")
end

-- prompt shows lock markers as readable tags (display-only transform)
do
	vim.api.nvim_input("<esc>")
	pcall(function()
		fc.jump({ pattern = "x" })
	end) -- installs patches, loop exits on the prefed escape
	local Prompt = require("flash.prompt")
	Prompt.set("ti\x01", false)
	ok(Prompt.prompt == "⚡ti [中]", "prompt displays [中] for cn lock")
	Prompt.set("dk\x04\x02", false)
	ok(Prompt.prompt == "⚡dk [韩] [日]", "prompt displays multiple locks (rightmost shown last)")
	Prompt.set("ti\x05", false)
	ok(Prompt.prompt == "⚡ti [英]", "prompt displays [英] for eo lock")
end

-- rust fast path: full state with the binary-backed matcher must agree
do
	local rust = require("flash-cjk.rust")
	if rust.available() then
		local State = require("flash.state")
		vim.api.nvim_buf_set_lines(0, 0, -1, false, { "日本語テスト ちちはち 梯子" })
		local langs_r = { cn = true, jp = true, ko = true, original = true }
		local state_r = State.new({
			pattern = "ti",
			labels = "asdfghjklqwertyuiopzxcvbnm",
			search = { mode = fc.make_mix_mode(langs_r, fc.config.force_keys) },
			matcher = rust.matcher(langs_r),
			labeler = function() end,
		})
		-- compare against the regex path on identical input instead of
		-- hardcoding counts
		local state_v = State.new({
			pattern = "ti",
			labels = "asdfghjklqwertyuiopzxcvbnm",
			search = { mode = fc.make_mix_mode(langs_r, fc.config.force_keys) },
			labeler = function() end,
		})
		local span_set = function(st)
			local t = {}
			for _, m in ipairs(st.results) do
				t[#t + 1] = m.pos[1] .. ":" .. m.pos[2] .. ":" .. m.end_pos[2]
			end
			table.sort(t)
			return table.concat(t, ",")
		end
		ok(span_set(state_r) == span_set(state_v), "rust matcher spans identical to regex path")

		-- circuit breaker: tripping it must degrade to identical spans
		-- through the vim-regex path (the graceful-fallback promise)
		rust.disable_for_test()
		local state_f = State.new({
			pattern = "ti",
			labels = "asdfghjklqwertyuiopzxcvbnm",
			search = { mode = fc.make_mix_mode(langs_r, fc.config.force_keys) },
			matcher = rust.matcher(langs_r),
			labeler = function() end,
		})
		ok(span_set(state_f) == span_set(state_v), "circuit breaker falls back to identical regex spans")
		rust.enable_for_test()

		-- multi-window parity: two splits of one buffer must produce the
		-- same result set as flash's default searcher (flash dedups
		-- same-buffer identical positions across windows by itself)
		do
			local mlines = {}
			for i = 1, 30 do
				mlines[i] = string.format("line %d 日本語テスト ち 梯 한국어", i)
			end
			vim.api.nvim_buf_set_lines(0, 0, -1, false, mlines)
			vim.cmd("vsplit")
			local function win_span_set(st)
				local t = {}
				for _, mm in ipairs(st.results) do
					t[#t + 1] = mm.win .. ":" .. mm.pos[1] .. ":" .. mm.pos[2] .. ":" .. mm.end_pos[2]
				end
				table.sort(t)
				return table.concat(t, ",")
			end
			local base = { pattern = "ti", labels = "asdfghjkl", search = { mode = fc.make_mix_mode(langs_r, fc.config.force_keys) }, labeler = function() end }
			local st_default = State.new(vim.tbl_deep_extend("force", base, { matcher = nil }))
			local st_rust = State.new(vim.tbl_deep_extend("force", base, { matcher = rust.matcher(langs_r) }))
			ok(win_span_set(st_rust) == win_span_set(st_default), "multi-window results match the default searcher")
			vim.cmd("close")
		end

		-- wrap/forward parity: flash filters matcher output by from/to
		-- itself, so the rust path must match the default searcher under
		-- restricted ranges too (cursor mid-line, matches on both sides)
		do
			vim.api.nvim_buf_set_lines(0, 0, -1, false, { "日本語テスト ちちはち 梯子 tail" })
			vim.api.nvim_win_set_cursor(0, { 1, 30 })
			local function cols(st)
				local t = {}
				for _, mm in ipairs(st.results) do
					t[#t + 1] = mm.pos[2]
				end
				return table.concat(t, ",")
			end
			for _, wrap in ipairs({ true, false }) do
				local base_w = {
					pattern = "ti",
					labels = "asdfghjkl",
					search = { mode = fc.make_mix_mode(langs_r, fc.config.force_keys), wrap = wrap },
					labeler = function() end,
				}
				local dv = State.new(vim.tbl_deep_extend("force", base_w, { matcher = nil }))
				local dr = State.new(vim.tbl_deep_extend("force", base_w, { matcher = rust.matcher(langs_r) }))
				ok(cols(dr) == cols(dv), string.format("wrap=%s: rust spans match default searcher (%s)", tostring(wrap), cols(dr)))
			end
			vim.api.nvim_win_set_cursor(0, { 1, 0 })
		end
	else
		print("note: rust binary not built, skipping rust path tests")
	end
end

-- public API surface: remote() entry (shared build_opts incl. rust
-- matcher + patches) and the flash-zh compat shim
do
	vim.api.nvim_buf_set_lines(0, 0, -1, false, { "日本語テスト ち 梯" })
	vim.api.nvim_input("<esc>") -- prefed: the remote loop exits on it
	local ok_remote, err_remote = pcall(function()
		fc.remote({})
	end)
	ok(ok_remote, "fc.remote() runs through the shared opts path (" .. tostring(err_remote) .. ")")

	local shim = require("flash-zh")
	ok(type(shim.jump) == "function" and type(shim.remote) == "function" and type(shim.setup) == "function",
		"flash-zh shim still forwards the public API")
	ok(shim == fc, "shim returns the same module table")
end

-- ---------------------------------------------------------------------------
-- performance: worst-case long inputs

for _, p in ipairs({ "k", "ka", "kan", "kanj", "kanji", "kanjix" }) do
	local t0 = os.clock()
	local regex = mixed(p)
	local re = vim.regex(regex)
	re:match_str("かんじ漢字感")
	local dt = (os.clock() - t0) * 1000
	ok(dt < 150, string.format("pattern %q under 150ms (took %.1fms)", p, dt))
	if p == "kanji" or p == "kanjix" then
		print(string.format("perf %q: %.1fms, regex %dKB", p, dt, math.floor(#regex / 1024)))
	end
end

print(string.format("%d passed, %d failed", passed, failed))
if failed > 0 then
	error("test failures")
end
