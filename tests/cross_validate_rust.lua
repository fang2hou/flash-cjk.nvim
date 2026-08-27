-- Strict rust/vim-regex parity cross-validation plus seeded fuzz: for each
-- pattern the span sequences of both paths must be identical item by
-- item (vim reports non-overlapping leftmost matches). Run:
--   nvim --headless -l tests/cross_validate_rust.lua
-- Requires the release binary: cargo build --release --manifest-path rust/Cargo.toml
package.path = "./lua/?.lua;./lua/?/init.lua;.deps/flash.nvim/lua/?.lua;.deps/flash.nvim/lua/?/init.lua;"
	.. package.path

local fc = require("flash-cjk")
local rust = require("flash-cjk.rust")

if not rust.available() then
	print("SKIP: rust binary not built (cd rust && cargo build --release)")
	return
end

-- Route every rust.search through the persistent server transport
-- when possible, so the strict parity + fuzz below exercise the UDS
-- path end to end (the same transport live keystrokes use).
if vim.fn.has("unix") == 1 then
	vim.env.XDG_RUNTIME_DIR = (vim.env.TMPDIR or "/tmp") .. "/fcjk-xval-" .. vim.uv.os_getpid()
	rust.reset_server_for_test()
	rust.warmup()
	assert(
		vim.wait(4000, function()
			return rust.server_ready()
		end, 10),
		"server transport failed to warm up"
	)
	print("transport: server (UDS)")
else
	print("transport: spawn (no UDS on this platform)")
end

local langs = { zhcn = true, ja = true, ko = true, en = true }

local lines = {
	"日本語テスト ちちはち 梯子 한국어 안녕하세요",
	"中文混合 english 你好世界 annyeong",
	"きょうと京都 학교 김치 time",
	"にほんご 日本語 대 한 中",
	"句读测试。全角，句号『引号』、顿号!感叹?dashーーend",
	"dict.key value,foo-bar [bracket] 'quote' \"dbl\" 5%",
	"きって きった キッテ まっちゃ まっすぐ チェック コーヒー ケーキ コヒー った っちゃ っぽ っし",
}

local function vim_spans(p, ls)
	local regex = fc.mix_mode(p)
	local spans = {}
	for li, line in ipairs(ls) do
		local col = 0
		while true do
			local s0, e0 = vim.regex(regex):match_str(line:sub(col + 1))
			if not s0 then
				break
			end
			spans[#spans + 1] = string.format("%d:%d+%d", li, col + s0, e0 - s0)
			col = col + e0
			-- a scan must advance; `<=` also rejects an impossible end<start regression
			if e0 <= s0 then
				break
			end
		end
	end
	return spans
end

-- returns the span list plus the raw matches and response: the fuzz phase
-- reuses them for pred_langs attribution
local function rust_spans(p, ls)
	local resp = rust.search(p, ls, langs)
	local found = (resp and resp.matches) or {}
	local spans = {}
	for _, m in ipairs(found) do
		spans[#spans + 1] = string.format("%d:%d+%d", m[1] + 1, m[2], m[4])
	end
	return spans, found, resp
end

local patterns = {
	"ni",
	"r",
	"ti",
	"kim",
	"gim",
	"dkss",
	"sha",
	"ho",
	"go",
	"kyo",
	"nihongo",
	"aoi",
	"ue",
	"an",
	"han",
	"hak",
	"gkr",
	"seoul",
	"annyeo",
	"ti\x01",
	"ti\x02",
	"ti\x04",
	"dkss\x04",
	"nih",
	".",
	",",
	"-",
	"?",
	"!",
	"[",
	"]",
	"a.",
	"ni,",
	"ho.",
	"dk,",
	"t-",
	"kitte",
	"kitta",
	"matcha",
	"massugu",
	"chekku",
	"koohii",
	"keeki",
	"kohi-",
	"tta",
	"tcha",
	"ppo",
	"sshi",
}

-- Strict comparison: both sides scan left-to-right non-overlapping, so
-- the span sequences must be identical item by item.
local fails = 0
for _, p in ipairs(patterns) do
	local vs = vim_spans(p, lines)
	local rs = rust_spans(p, lines)
	if #vs ~= #rs then
		fails = fails + 1
		print(string.format("COUNT MISMATCH %q: vim=%d rust=%d", p, #vs, #rs))
	else
		for i = 1, #vs do
			if vs[i] ~= rs[i] then
				fails = fails + 1
				print(string.format("SPAN MISMATCH %q #%d: vim=%s rust=%s", p, i, vs[i], rs[i]))
			end
		end
	end
	print(
		string.format(
			"%-12s spans=%-2d %s",
			("%q"):format(p):sub(1, 12),
			#vs,
			#vs == #rs and "identical" or "DIFF"
		)
	)
end
if fails > 0 then
	error(fails .. " cross-validation failures")
end
print("CROSS-VALIDATION PASSED (strict equality)")

-- ---------------------------------------------------------------------------
-- protocol shape: every response must carry per-match language tags
-- parallel to the matches
do
	local valid = { zhcn = true, ja = true, ko = true, en = true }
	local checked = 0
	for _, p in ipairs(patterns) do
		local resp = rust.search(p, lines, langs)
		local tags = resp and resp.pred_langs
		if tags == nil then
			error(("protocol: pred_langs missing for %q"):format(p))
		end
		if #tags ~= #(resp or {}).matches then
			error(("protocol: pred_langs not parallel to matches for %q"):format(p))
		end
		for _, entry in ipairs(tags) do
			if type(entry) ~= "table" then
				error(("protocol: pred_langs entry not an array for %q"):format(p))
			end
			for _, lang in ipairs(entry) do
				if not valid[lang] then
					error(("protocol: unknown language tag %q"):format(lang))
				end
				checked = checked + 1
			end
		end
	end
	print(string.format("PRED_LANGS PASSED (%d tags over %d patterns)", checked, #patterns))
end

-- ---------------------------------------------------------------------------
-- fuzz: random patterns and mixed-CJK lines, vim vs rust must agree
math.randomseed(42) -- deterministic
local alphabet = {
	"a",
	"e",
	"i",
	"o",
	"u",
	"n",
	"k",
	"s",
	"t",
	"h",
	"d",
	"r",
	"g",
	"b",
	"m",
	"y",
	"c",
	"l",
	"p",
	"z",
}
local soup = {
	"日",
	"本",
	"語",
	"テ",
	"ス",
	"ト",
	"で",
	"す",
	"ち",
	"梯",
	"子",
	"韓",
	"国",
	"語",
	"安",
	"녕",
	"하",
	"세",
	"요",
	"你",
	"好",
	"中",
	"文",
	"x",
	"y",
	"z",
	"0",
	"1",
	" ",
	" ",
}
local function rand_line()
	local n = math.random(8, 40)
	local parts = {}
	for i = 1, n do
		parts[i] = soup[math.random(#soup)]
	end
	return table.concat(parts)
end
local function rand_pattern()
	local n = math.random(1, 5)
	local parts = {}
	for i = 1, n do
		parts[i] = alphabet[math.random(#alphabet)]
	end
	local p = table.concat(parts)
	if math.random() < 0.25 then
		-- inject a lock marker at a random position
		local markers = { "\x01", "\x02", "\x04", "\x05" }
		local pos = math.random(0, #p)
		p = p:sub(1, pos) .. markers[math.random(#markers)] .. p:sub(pos + 1)
		p = p:gsub("\x01", "\x01"):gsub("\x02", "\x02"):gsub("\x04", "\x04"):gsub("\x05", "\x05")
	end
	return p
end

-- Lua attribution of one rust-reported match (line/col/len are the
-- binary's: 0-based line, byte col, byte length), mirroring the
-- predictor's text window: the match plus the following character
local function vim_attr_for(p, line, col, len)
	local char_size = require("flash-cjk.util").char_size
	local match_end = col + len -- 1-based inclusive end byte
	local text = string.sub(line, col + 1, match_end + char_size(line, match_end + 1))
	return require("flash-cjk.labeler").match_langs(text, (fc.parse_filter(p)), langs)
end

local function attr_key(t)
	local copy = {}
	for i, v in ipairs(t) do
		copy[i] = v
	end
	table.sort(copy)
	return table.concat(copy, ",")
end

local fuzz_fails = 0
local attr_checked = 0
for round = 1, 300 do
	local ls, p = { rand_line(), rand_line(), rand_line() }, rand_pattern()
	local vs = vim_spans(p, ls)
	local rs, found, resp = rust_spans(p, ls)
	if #vs ~= #rs then
		fuzz_fails = fuzz_fails + 1
		print(string.format("FUZZ COUNT round=%d pattern=%q vim=%d rust=%d", round, p, #vs, #rs))
	else
		for i = 1, #vs do
			if vs[i] ~= rs[i] then
				fuzz_fails = fuzz_fails + 1
				print(
					string.format(
						"FUZZ SPAN round=%d pattern=%q #%d vim=%s rust=%s",
						round,
						p,
						i,
						vs[i],
						rs[i]
					)
				)
				break
			end
		end
		-- attribution parity: spans already agree item by item, so the
		-- rust prediction tags and the Lua spelling attribution must
		-- match on every match
		local tags = (resp and resp.pred_langs) or {}
		for i, m in ipairs(found) do
			local va = vim_attr_for(p, ls[m[1] + 1], m[2], m[4])
			if attr_key(va) ~= attr_key(tags[i] or {}) then
				fuzz_fails = fuzz_fails + 1
				print(
					string.format(
						"ATTR round=%d pattern=%q #%d vim=%s rust=%s",
						round,
						p,
						i,
						attr_key(va),
						attr_key(tags[i] or {})
					)
				)
			end
			attr_checked = attr_checked + 1
		end
	end
end
if fuzz_fails > 0 then
	error(fuzz_fails .. " fuzz failures")
end
print(
	string.format(
		"FUZZ CROSS-VALIDATION PASSED (300 rounds, strict equality, %d attributions)",
		attr_checked
	)
)
