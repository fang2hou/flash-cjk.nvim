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
ok(matches(mixed, "tu", "つ"), "kunrei tu matches つ")
ok(matches(mixed, "ni", "你"), "ni matches 你 (zh pinyin)")
ok(matches(mixed, "tsu", "津"), "tsu matches 津")
ok(matches(mixed, "n", "ん"), "n matches ん")

-- language-specific: these must NOT cross over
ok(not matches(jp_only, "r", "人"), "jp-only: pinyin r does not match 人")
ok(matches(jp_only, "hi", "人"), "jp-only: hi matches 人 (hito)")
ok(not matches(cn_only, "ni", "に"), "zh-only: ni does not match kana に")
ok(matches(cn_only, "ni", "你"), "zh-only: ni matches 你")
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
	"日本語テストです",
	"中文混合 english 你好",
	"きょうと京都",
})
vim.api.nvim_win_set_cursor(0, { 1, 0 })

local langs = { cn = true, jp = true, original = true }
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
