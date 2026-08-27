-- Behavior test suite: matcher, labeler and the public API. Run:
--   nvim --headless +"lua dofile('tests/run.lua')" +qa!
-- Requires flash.nvim; when missing it is cloned into .deps/ automatically.

local uv = vim.uv

local function setup_rtp()
	local root = vim.fs.normalize(uv.cwd() or "")
	if root:match("tests$") then
		root = vim.fs.dirname(root)
	end
	vim.opt.rtp:prepend(root)
	local deps = root .. "/.deps"
	local flash_dep = deps .. "/flash.nvim"
	if not uv.fs_stat(flash_dep) then
		vim.fn.mkdir(deps, "p")
		vim.system({
			"git",
			"clone",
			"--depth",
			"1",
			"https://github.com/folke/flash.nvim",
			flash_dep,
		}):wait()
	end
	vim.opt.rtp:prepend(flash_dep)
	return root
end

setup_rtp()

local fc = require("flash-cjk")
local cfg = require("flash-cjk.config")
local ja = require("flash-cjk.lang.ja")
local ko = require("flash-cjk.lang.ko")

local passed, failed = 0, 0
local function ok(cond, msg)
	if cond then
		passed = passed + 1
	else
		failed = failed + 1
		io.stderr:write("FAIL: " .. msg .. "\n")
	end
end

local function matches(pattern_fn, pattern, text)
	local regex = pattern_fn(pattern)
	local re = vim.regex(regex)
	return re:match_str(text) ~= nil
end

local mixed = fc.make_mix_mode({ zhcn = true, ja = true, en = true })
local zh_only = fc.make_mix_mode({ zhcn = true, ja = false, en = true })
local ja_only = fc.make_mix_mode({ zhcn = false, ja = true, en = true })
local en_only = fc.make_mix_mode({ zhcn = false, ja = false, en = true })
local no_en = fc.make_mix_mode({ zhcn = true, ja = true, en = false })

-- ---------------------------------------------------------------------------
-- data sanity

ok(ja.pattern("ni"):match("日", 1), "p2.ni contains 日")
ok(ja.pattern("ni"):match("に", 1), "p2.ni contains に")
ok(ja.pattern("ni"):match("ニ", 1), "p2.ni contains ニ")
ok(ja.pattern("tsu") and ja.pattern("tsu"):match("つ", 1), "p3.tsu contains つ")
ok(ja.pattern("sha") and ja.pattern("sha"):match("しゃ", 1), "p3.sha contains しゃ combo")
ok(not matches(ja_only, "ni", "们"), "jp-only: ni does not match zh-only char 们")

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
ok(matches(mixed, "kitte", "きって"), "kitte matches きって (geminate kk)")
ok(matches(mixed, "kitte", "キッテ"), "kitte matches キッテ (katakana geminate)")
ok(matches(mixed, "kitta", "切った"), "kitta matches 切った (kanji + geminate)")
ok(matches(mixed, "kitta", "きった"), "kitta matches きった")
ok(matches(mixed, "matcha", "まっちゃ"), "matcha matches まっちゃ (t before ch)")
ok(matches(mixed, "massugu", "まっすぐ"), "massugu matches まっすぐ (geminate ss)")
ok(matches(mixed, "chekku", "チェック"), "chekku matches チェック (youon + geminate)")
ok(matches(mixed, "koohii", "コーヒー"), "koohii matches コーヒー (long vowel)")
ok(matches(mixed, "keeki", "ケーキ"), "keeki matches ケーキ (long vowel)")
ok(matches(mixed, "ko-hi-", "コーヒー"), "ko-hi- still matches コーヒー (dash input)")

-- Korean: romanization + two-set, both at once
local trilingual = fc.make_mix_mode({ zhcn = true, ja = true, ko = true, en = true })
ok(matches(trilingual, "kim", "김"), "kim matches 김 (RR)")
ok(
	matches(fc.make_mix_mode({ zhcn = false, ja = false, ko = true, en = false }), "kim", "김"),
	"kim matches 김 (ko only)"
)
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
ok(
	not matches(fc.make_mix_mode({ zhcn = true, ja = true, ko = false, en = true }), "kim", "김"),
	"ko off: kim does not match 김"
)

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

-- ko self-check: hand-written jamo facts, asserted here instead of at
-- module load (the user's runtime never executes them)
local ok_sc, err_sc = pcall(ko.self_check)
ok(ok_sc, "ko.self_check: hand-written facts hold (" .. tostring(err_sc) .. ")")

-- mixed_input = false: language->literal tails dropped, every pure chain still matches
local pure = fc.make_mix_mode({ zhcn = true, ja = true, ko = true, en = true, mixed_input = false })
ok(matches(pure, "kim", "김"), "pure: kim matches 김")
ok(matches(pure, "dkss", "안녕"), "pure: dkss matches 안녕")
ok(matches(pure, "niho", "日本"), "pure: niho matches 日本")

-- mid-input language forcing (C-p / C-n / C-k markers)
ok(
	fc.parse_filter("ti\x01") == "ti" and select(2, fc.parse_filter("ti\x01")) == "zhcn",
	"parse_filter: cn marker"
)
ok(select(2, fc.parse_filter("ti\x02")) == "ja", "parse_filter: jp marker")
ok(select(2, fc.parse_filter("ti\x04")) == "ko", "parse_filter: ko marker")
ok(select(2, fc.parse_filter("ti\x05")) == "en", "parse_filter: en marker")
ok(select(2, fc.parse_filter("ti\x01\x02")) == "ja", "parse_filter: rightmost marker wins")
ok(select(2, fc.parse_filter("ti")) == nil, "parse_filter: no marker")
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
ok(not matches(ja_only, "r", "人"), "jp-only: pinyin r does not match 人")
ok(matches(ja_only, "hi", "人"), "jp-only: hi matches 人 (hito)")
ok(not matches(zh_only, "ni", "に"), "zh-only: ni does not match kana に")
ok(matches(zh_only, "ni", "你"), "zh-only: ni matches 你")
-- per-jump filter_keys: mode must honor the jump-specific keys
local per_jump = fc.make_mix_mode(
	{ zhcn = true, ja = true, ko = true, en = true },
	{ zhcn = "<C-d>" }
)
ok(not matches(per_jump, "ti\x01", "ち"), "per-jump keys: cn marker still locks cn")
ok(
	not matches(per_jump, "ti\x02", "ち"),
	"per-jump keys: unbound ja marker is inert (no lock, no match)"
)
local clean2, locked2 = fc.parse_filter("ti\x02", { zhcn = "<C-d>" })
ok(clean2 == "ti\x02" and locked2 == nil, "per-jump keys: unbound marker not stripped, not a lock")
-- empty marker set must not crash
ok(
	fc.parse_filter("ti", { zhcn = false, ja = false, ko = false }) == "ti",
	"all keys disabled: no crash, no strip"
)
ok(not matches(zh_only, "kyo", "京"), "zh-only: kyo does not match 京")
ok(matches(mixed, "kyo", "京"), "mixed: kyo matches 京")

-- en flag: plain literal letters, nothing else
ok(matches(en_only, "ni", "nice"), "en-only: ni matches nice")
ok(not matches(en_only, "ni", "你"), "en-only: ni does not match 你")
ok(not matches(en_only, "ni", "日"), "en-only: ni does not match 日")

-- en disabled: languages still match, literal letters do not
ok(matches(no_en, "ni", "你"), "en-off: ni still matches 你")
ok(matches(no_en, "ni", "日"), "en-off: ni still matches 日")
ok(not matches(no_en, "ni", "nice"), "en-off: ni does not match nice")
ok(matches(no_en, "1", "1"), "en-off: digits still match literally")
ok(matches(no_en, "n.", "n."), "en-off: uninterpretable input falls back to literal")

-- punctuation
ok(matches(mixed, "-", "ー"), "hyphen matches ー (jp)")
ok(not matches(zh_only, "-", "ー"), "zh-only: hyphen does not match ー")
ok(matches(mixed, ".", "。"), "dot matches 。")
ok(matches(mixed, ",", "、"), "comma matches 、")

-- punctuation follows the language switches too
ok(matches(ja_only, ",", "、"), "jp-only: comma matches 、")
ok(not matches(ja_only, ",", "，"), "jp-only: comma does not match fullwidth ，")
ok(matches(ja_only, ".", "。"), "jp-only: dot matches shared 。")
ok(not matches(zh_only, ",", "、"), "zh-only: comma does not match 、")
ok(matches(zh_only, ",", "，"), "zh-only: comma matches ，")
ok(matches(mixed, ",", "，"), "mixed: comma matches ，")

-- ---------------------------------------------------------------------------
-- labeler reading prediction

local strs = ja.strs("日本")
local found = false
for _, s in ipairs(strs) do
	if s == "nichihon" then
		found = true
	end
end
ok(found, "ja.strs(日本) includes nichihon")

local sha_strs = ja.strs("しゃ")
found = false
for _, s in ipairs(sha_strs) do
	if s == "sha" then
		found = true
	end
end
ok(found, "ja.strs(しゃ) includes sha (youon merge)")

local matcha_strs = ja.strs("まっちゃ")
found = false
for _, s in ipairs(matcha_strs) do
	if s == "matcha" then
		found = true
	end
end
ok(found, "ja.strs(まっちゃ) includes matcha (geminate + youon merge)")

local koohii_strs = ja.strs("コーヒー")
local koohii_typed, kodash = false, false
for _, s in ipairs(koohii_strs) do
	if s == "koohii" then
		koohii_typed = true
	end
	if s == "ko-hi-" then
		kodash = true
	end
end
ok(koohii_typed, "ja.strs(コーヒー) includes koohii (long vowel spelling)")
ok(kodash, "ja.strs(コーヒー) includes ko-hi- (dash spelling)")

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
local langs = { zhcn = true, ja = true, ko = true, en = true }
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

-- filter_keys are configurable: remap cn to <C-d>, then verify and restore
fc.setup({
	languages = {
		zhcn = { filter_key = false },
		ja = { filter_key = false },
		ko = { filter_key = false },
	},
})
ok(fc.parse_filter("ti\x01") == "ti\x01", "all locks disabled: markers not stripped")
ok(select(2, fc.parse_filter("ti\x01")) == nil, "all locks disabled: no forced lang")
fc.setup({
	languages = {
		zhcn = { filter_key = "<C-c>" },
		ja = { filter_key = "<C-j>" },
		ko = { filter_key = "<C-k>" },
	},
}) -- restore defaults
do
	local State = require("flash.state")
	vim.api.nvim_buf_set_lines(0, 0, -1, false, { "日本語テスト ちちはち 梯子" })
	require("flash-cjk.patches").get_char_patch()
	local keys = cfg.filter_keys(fc.config.languages)
	local mode_e2e = fc.make_mix_mode(fc.resolve_langs(nil), keys)
	local fired = false
	local actions_e2e = {}
	local function lock(state, marker)
		-- mirrors build_opts: a new lock replaces any previous one
		local clean = fc.parse_filter(state.pattern.pattern)
		state:update({ pattern = clean .. marker })
		return true
	end
	local ja_key = vim.api.nvim_replace_termcodes(keys.ja, true, true, true)
	actions_e2e[ja_key] = function(state, _char)
		fired = true
		return lock(state, "\x02")
	end
	local ko_key = vim.api.nvim_replace_termcodes(keys.ko, true, true, true)
	actions_e2e[ko_key] = function(state, _char)
		return lock(state, "\x04")
	end
	local state_e2e = State.new({
		pattern = "",
		labels = "asdfghjklqwertyuiopzxcvbnm",
		search = { mode = mode_e2e },
		actions = actions_e2e,
		labeler = function(_, s)
			require("flash-cjk.labeler").new(s, fc.resolve_langs(nil), keys):update()
		end,
	})
	-- prefed <C-c> sets the interrupt flag before the loop can read the
	-- queued text, so the override sequence uses the two plain keys
	vim.api.nvim_input("ti<C-j><C-k><esc>")
	state_e2e:loop()
	ok(fired, "end-to-end: C-j action fires inside flash loop")
	ok(
		state_e2e.pattern.pattern == "ti\x04",
		"end-to-end: new lock replaces the previous one (only \x04 left)"
	)
	ok(#state_e2e.results == 0, "end-to-end: ko lock finds no Japanese-only matches")
end

-- prompt shows lock markers as readable tags (display-only transform)
do
	vim.api.nvim_input("<esc>")
	pcall(function()
		fc.jump()
	end) -- installs patches, loop exits on the prefed escape
	local Prompt = require("flash.prompt")
	Prompt.set("ti\x01", false)
	ok(Prompt.prompt == "⚡ti [中]", "prompt displays [中] for cn lock")
	Prompt.set("dk\x04\x02", false)
	ok(
		Prompt.prompt == "⚡dk [한] [日]",
		"prompt displays multiple markers (rightmost shown last)"
	)
	Prompt.set("ti\x05", false)
	ok(Prompt.prompt == "⚡ti [EN]", "prompt displays [EN] for en lock")
end

-- rust fast path: full state with the binary-backed matcher must agree
do
	local rust = require("flash-cjk.rust")
	if rust.available() then
		local State = require("flash.state")
		vim.api.nvim_buf_set_lines(0, 0, -1, false, { "日本語テスト ちちはち 梯子" })
		local langs_r = { zhcn = true, ja = true, ko = true, en = true }
		local default_keys = cfg.filter_keys(fc.config.languages)
		local state_r = State.new({
			pattern = "ti",
			labels = "asdfghjklqwertyuiopzxcvbnm",
			search = { mode = fc.make_mix_mode(langs_r, default_keys) },
			matcher = rust.matcher(langs_r),
			labeler = function() end,
		})
		-- compare against the regex path on identical input instead of
		-- hardcoding counts
		local state_v = State.new({
			pattern = "ti",
			labels = "asdfghjklqwertyuiopzxcvbnm",
			search = { mode = fc.make_mix_mode(langs_r, default_keys) },
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
			search = { mode = fc.make_mix_mode(langs_r, default_keys) },
			matcher = rust.matcher(langs_r),
			labeler = function() end,
		})
		ok(
			span_set(state_f) == span_set(state_v),
			"circuit breaker falls back to identical regex spans"
		)
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
					t[#t + 1] = mm.win
						.. ":"
						.. mm.pos[1]
						.. ":"
						.. mm.pos[2]
						.. ":"
						.. mm.end_pos[2]
				end
				table.sort(t)
				return table.concat(t, ",")
			end
			local base = {
				pattern = "ti",
				labels = "asdfghjkl",
				search = { mode = fc.make_mix_mode(langs_r, default_keys) },
				labeler = function() end,
			}
			local st_default = State.new(vim.tbl_deep_extend("force", base, { matcher = nil }))
			local st_rust =
				State.new(vim.tbl_deep_extend("force", base, { matcher = rust.matcher(langs_r) }))
			ok(
				win_span_set(st_rust) == win_span_set(st_default),
				"multi-window results match the default searcher"
			)
			vim.cmd("close")
		end

		-- wrap/forward parity: flash filters matcher output by from/to
		-- itself, so the rust path must match the default searcher under
		-- restricted ranges too (cursor mid-line, matches on both sides)
		do
			vim.api.nvim_buf_set_lines(
				0,
				0,
				-1,
				false,
				{ "日本語テスト ちちはち 梯子 tail" }
			)
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
					search = { mode = fc.make_mix_mode(langs_r, default_keys), wrap = wrap },
					labeler = function() end,
				}
				local dv = State.new(vim.tbl_deep_extend("force", base_w, { matcher = nil }))
				local dr = State.new(
					vim.tbl_deep_extend("force", base_w, { matcher = rust.matcher(langs_r) })
				)
				ok(
					cols(dr) == cols(dv),
					string.format(
						"wrap=%s: rust spans match default searcher (%s)",
						tostring(wrap),
						cols(dr)
					)
				)
			end
			vim.api.nvim_win_set_cursor(0, { 1, 0 })
		end

		-- scrolled window regression: the visible slice starts at
		-- line("w0") > 1, so relative line indices must be converted to
		-- absolute buffer lines (before the fix every match was dropped
		-- by flash's from/to filter and jump exited with zero results)
		do
			local slines = {}
			for i = 1, 120 do
				slines[i] = (i % 7 == 0) and ("row " .. i .. " 日本語テスト ち 梯")
					or ("filler " .. i)
			end
			vim.api.nvim_buf_set_lines(0, 0, -1, false, slines)
			vim.api.nvim_win_set_cursor(0, { 60, 0 })
			vim.cmd("normal! zt") -- scroll: visible top is now line 60
			local w0 = vim.fn.line("w0")
			ok(w0 > 1, "scrolled setup: window top is past line 1 (w0=" .. w0 .. ")")
			local base_s = {
				pattern = "ti",
				labels = "asdfghjkl",
				search = { mode = fc.make_mix_mode(langs_r, default_keys) },
				labeler = function() end,
			}
			local st_d = State.new(vim.tbl_deep_extend("force", base_s, { matcher = nil }))
			local st_r =
				State.new(vim.tbl_deep_extend("force", base_s, { matcher = rust.matcher(langs_r) }))
			local function lines_set(st)
				local t = {}
				for _, mm in ipairs(st.results) do
					t[#t + 1] = mm.pos[1] .. ":" .. mm.pos[2]
				end
				table.sort(t)
				return table.concat(t, ",")
			end
			ok(#st_r.results > 0, "scrolled window: rust matcher returns visible matches")
			ok(
				lines_set(st_r) == lines_set(st_d),
				"scrolled window: rust spans (absolute lines) match default searcher"
			)
			vim.api.nvim_win_set_cursor(0, { 1, 0 })
			vim.cmd("normal! gg")
		end
	else
		print("note: rust binary not built, skipping rust path tests")
	end
end

-- persistent-server transport: the UDS path must return exactly what
-- the spawn path returns, and transport failures (timeout, crashed
-- server) must degrade to the spawn path without erroring
do
	local rust = require("flash-cjk.rust")
	if rust.available() and vim.fn.has("unix") == 1 then
		local saved_rt = vim.env.XDG_RUNTIME_DIR
		vim.env.XDG_RUNTIME_DIR = (vim.env.TMPDIR or "/tmp") .. "/fcjk-run-" .. vim.uv.os_getpid()
		rust.reset_server_for_test()
		rust.warmup()
		local ready = vim.wait(4000, function()
			return rust.server_ready()
		end, 10)
		ok(ready, "server transport: warmup opened a session")
		if ready then
			local lines_t = { "日本語テスト ちちはち 梯子 안녕", "hello 日本 nice" }
			local langs_t = { zhcn = true, ja = true, ko = true, en = true }
			local same = true
			for _, p in ipairs({ "ti", "ni", "sha", "dkss", "ti\x02", "n", "han" }) do
				local a = rust.search(p, lines_t, langs_t)
				local b = rust.search_spawn(p, lines_t, langs_t)
				if vim.inspect(a) ~= vim.inspect(b) then
					same = false
				end
			end
			ok(
				same,
				"server transport: responses identical to spawn transport (spans + pred_langs)"
			)

			-- a per-request budget that cannot be met must fall back to
			-- the spawn transport silently for that keystroke
			rust.set_server_timeout_for_test(1)
			local fell_back_ok = true
			for _, p in ipairs({ "ti", "ni" }) do
				local r = rust.search(p, lines_t, langs_t)
				if not r or type(r.matches) ~= "table" then
					fell_back_ok = false
				end
			end
			rust.set_server_timeout_for_test(200)
			ok(fell_back_ok, "server transport: timeout falls back to spawn without error")

			-- crash recovery: kill -9 the server; the next keystroke must
			-- fall back and a replacement server must come up
			local addr = rust.server_addr()
			local srv = vim.fn.trim(
				vim.fn.system(("pgrep -f 'flash-cjk-search serve --socket %s'"):format(addr)) or ""
			)
			if srv ~= "" then
				vim.fn.system(("kill -9 %s"):format(srv))
			end
			vim.wait(300, function()
				return false
			end) -- let the exit land
			local r2 = rust.search("ti", lines_t, langs_t)
			local revived = vim.wait(4000, function()
				return rust.server_ready()
			end, 10)
			local r3 = rust.search("ti", lines_t, langs_t)
			ok(
				r2 ~= nil and revived and r3 ~= nil and #r3.matches > 0,
				"server transport: crash -> spawn fallback -> revive"
			)
		end
		vim.env.XDG_RUNTIME_DIR = saved_rt
		rust.reset_server_for_test()
	end
end

-- public API surface: remote() entry (shared build_opts incl. rust
-- matcher + patches)
do
	vim.api.nvim_buf_set_lines(0, 0, -1, false, { "日本語テスト ち 梯" })
	vim.api.nvim_input("<esc>") -- prefed: the remote loop exits on it
	local ok_remote, err_remote = pcall(function()
		fc.remote()
	end)
	ok(ok_remote, "fc.remote() runs through the shared opts path (" .. tostring(err_remote) .. ")")
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

-- ---------------------------------------------------------------------------
-- languages config API: shorthand normalization, deep merge, overrides

do
	local saved = vim.deepcopy(fc.config)
	fc.setup({ languages = { zhcn = true } })
	ok(fc.config.languages.zhcn.enabled, "setup: true shorthand enables the language")
	fc.setup({ languages = { zhcn = false } })
	ok(fc.config.languages.zhcn.enabled == false, "setup: false shorthand disables the language")
	fc.setup({ languages = { ja = { filter_key = "<C-d>" } } })
	ok(
		fc.config.languages.ja.filter_key == "<C-d>",
		"setup: field-level deep merge keeps unspecified fields"
	)
	ok(
		fc.config.languages.ko.filter_key == "<C-k>",
		"setup: deep merge leaves other languages alone"
	)
	fc.setup({ languages = { en = { filter_key = "<M-e>" } } })
	ok(
		fc.config.languages.en.filter_key == "<M-e>" and fc.config.languages.en.enabled,
		"setup: built-in en merges onto its built-in defaults"
	)
	fc.config = vim.deepcopy(saved)
	ok(
		cfg.filter_keys(fc.config.languages).en == "<C-e>",
		"defaults: en keeps its built-in filter_key"
	)
	ok(
		vim.inspect(fc.config.priority) == vim.inspect({ "zhcn", "ja", "ko" }),
		"defaults: priority { zhcn, ja, ko }"
	)
	ok(
		pcall(fc.setup, { languages = { zhcn = { filter_key = 42 } } }) == false,
		"setup: filter_key must be a string or false"
	)
	ok(pcall(fc.setup, { languages = { zhcn = 42 } }) == false, "setup: wrong entry type errors")
	ok(
		pcall(fc.setup, { languages = { xx = true } }) == false,
		"setup: unknown language code errors"
	)
	fc.config = vim.deepcopy(saved) -- defaults back for the resolve_langs checks
	local l = fc.resolve_langs(nil)
	ok(l.zhcn and l.ja and l.ko and l.en, "resolve_langs(nil): setup-enabled set (all defaults on)")
	l = fc.resolve_langs({ "zhcn", "en" })
	ok(
		l.zhcn and l.en and not l.ja and not l.ko,
		"resolve_langs: array fully decides the enabled set"
	)
	ok(pcall(fc.resolve_langs, { "kr" }) == false, "resolve_langs: kr alias removed")
	ok(pcall(fc.resolve_langs, { "xx" }) == false, "resolve_langs: unknown code errors")
	fc.setup({ languages = { ko = false } })
	ok(fc.resolve_langs({ "ko" }).ko, "resolve_langs: array overrides a setup-disabled language")
	local ja_en = fc.make_mix_mode(fc.resolve_langs({ "ja", "en" }))
	ok(matches(ja_en, "ti", "ち"), "ja+en mode: ti matches ち")
	ok(not matches(ja_en, "ti", "梯"), "ja+en mode: ti does not match 梯")
	fc.config = saved
end

-- ---------------------------------------------------------------------------
-- language priority: label-assignment order only

do
	local State = require("flash.state")
	local labeler_mod = require("flash-cjk.labeler")
	local all = { zhcn = true, ja = true, ko = true, en = true }
	local last_labeler

	local function priority_state(priority, pattern, buffer)
		vim.api.nvim_buf_set_lines(0, 0, -1, false, buffer)
		vim.api.nvim_win_set_cursor(0, { 1, 0 })
		return State.new({
			pattern = pattern,
			labels = "asdfghjklqwertyuiopzxcvbnm",
			search = { mode = fc.make_mix_mode(all) },
			labeler = function(_, s)
				last_labeler = labeler_mod.new(s, all, nil, priority)
				last_labeler:update()
			end,
		})
	end

	local function label_at(state, byte_col)
		for _, m in ipairs(state.results) do
			if m.pos[2] == byte_col then
				return m.label
			end
		end
	end

	-- position of a match's label in the pool: smaller = assigned
	-- earlier (the skip-set can remove early letters, so label bytes
	-- do not order)
	local function pool_pos(state, byte_col)
		local want = label_at(state, byte_col)
		for i, l in ipairs(last_labeler.labels) do
			if l == want then
				return i
			end
		end
	end

	local TI_BUF, TI_TI, TI_CN = { "x 梯 ち" }, 6, 2 -- byte cols of ち and 梯
	local st = priority_state({ "ja" }, "ti", TI_BUF)
	ok(pool_pos(st, TI_TI) < pool_pos(st, TI_CN), "priority ja: first label goes to the ja match")
	st = priority_state({ "zhcn" }, "ti", TI_BUF)
	ok(
		pool_pos(st, TI_CN) < pool_pos(st, TI_TI),
		"priority zhcn: first label goes to the zhcn match"
	)
	st = priority_state(nil, "ti", TI_BUF)
	ok(
		pool_pos(st, TI_CN) < pool_pos(st, TI_TI),
		"no priority: position order (leftmost labeled first)"
	)

	-- multi-interpretation attribution: 梯 extends "t" through BOTH
	-- xiaohe (ti) and Japanese readings (tai/tei), so a ja priority
	-- keeps it top-ranked alongside ち, while zhcn promotes it over the
	-- leftmost ち (the reverse buffer makes the flip observable)
	local T_BUF, T_TI, T_CN = { "x ち 梯" }, 2, 6
	st = priority_state({ "zhcn" }, "t", T_BUF)
	ok(
		pool_pos(st, T_CN) < pool_pos(st, T_TI),
		"multi-interpretation: zhcn priority promotes 梯 (zhcn+ja) over ち"
	)
	st = priority_state({ "ja" }, "t", T_BUF)
	ok(
		pool_pos(st, T_TI) < pool_pos(st, T_CN),
		"multi-interpretation: ja priority keeps position order (梯 counts as ja too)"
	)
	st = priority_state(nil, "t", T_BUF)
	ok(
		pool_pos(st, T_TI) < pool_pos(st, T_CN),
		"multi-interpretation: no priority keeps position order"
	)

	-- attribution of one text: engines whose spellings extend the
	-- prefix; literal ASCII spans belong to en
	local ml = labeler_mod.match_langs("梯x", "t", all)
	local has_zh, has_ja = false, false
	for _, lang in ipairs(ml) do
		has_zh = has_zh or lang == "zhcn"
		has_ja = has_ja or lang == "ja"
	end
	ok(has_zh and has_ja, "match_langs: 梯 attributed to zhcn and ja for prefix t")
	ml = labeler_mod.match_langs("ちx", "ti", all)
	ok(#ml == 1 and ml[1] == "ja", "match_langs: ち attributed to ja only")
	ml = labeler_mod.match_langs("timex", "ti", all)
	ok(#ml == 1 and ml[1] == "en", "match_langs: literal ASCII span attributed to en")
	ml = labeler_mod.match_langs("timex", "ti", { zhcn = true, ja = true, ko = true, en = false })
	ok(#ml == 0, "match_langs: en attribution follows the enabled flags")

	-- config validation: storage, dedupe, errors
	local saved = vim.deepcopy(fc.config)
	fc.setup({ priority = { "ja", "zhcn" } })
	ok(
		vim.inspect(fc.config.priority) == vim.inspect({ "ja", "zhcn" }),
		"setup: priority stored in order"
	)
	fc.setup({ priority = { "ja", "ja", "ko" } })
	ok(
		vim.inspect(fc.config.priority) == vim.inspect({ "ja", "ko" }),
		"setup: priority duplicates dropped"
	)
	ok(pcall(fc.setup, { priority = { "xx" } }) == false, "setup: unknown priority code errors")
	ok(pcall(fc.setup, { priority = "ja" }) == false, "setup: non-array priority errors")
	fc.config = saved
	ok(
		vim.inspect(fc.config.priority) == vim.inspect({ "zhcn", "ja", "ko" }),
		"config restore: default priority back"
	)
end

print(string.format("%d passed, %d failed", passed, failed))
if failed > 0 then
	error("test failures")
end
