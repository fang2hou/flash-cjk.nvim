-- Cross-validation: for each pattern, the Rust matcher's span set must
-- be a superset of the vim-regex spans (vim reports non-overlapping
-- leftmost matches; Rust reports all spans including overlaps).
package.path = "./lua/?.lua;./lua/?/init.lua;.deps/flash.nvim/lua/?.lua;.deps/flash.nvim/lua/?/init.lua;" .. package.path

local fc = require("flash-cjk")
local rust = require("flash-cjk.rust")

if not rust.available() then
	print("SKIP: rust binary not built (cd rust && cargo build --release)")
	return
end

local langs = { cn = true, jp = true, ko = true, original = true }

local lines = {
	"日本語テスト ちちはち 梯子 한국어 안녕하세요",
	"中文混合 english 你好世界 annyeong",
	"きょうと京都 학교 김치 time",
	"にほんご 日本語 대 한 中",
	"句读测试。全角，句号『引号』、顿号!感叹?dashーーend",
	"dict.key value,foo-bar [bracket] 'quote' \"dbl\" 5%",
}

local function vim_spans(pattern)
	local regex = fc.mix_mode(pattern)
	local spans = {}
	for li, line in ipairs(lines) do
		local col = 0
		while true do
			local s, e = vim.regex(regex):match_str(line:sub(col + 1))
			if not s then
				break
			end
			spans[#spans + 1] = string.format("%d:%d+%d", li, col + s, e - s)
			col = col + e
			if e == s then
				break
			end
		end
	end
	return spans
end

local function rust_spans(pattern)
	local resp = rust.search(pattern, lines, langs)
	local found = (resp and resp.matches) or {}
	local spans = {}
	for _, m in ipairs(found) do
		spans[#spans + 1] = string.format("%d:%d+%d", m[1] + 1, m[2], m[4])
	end
	return spans
end

local patterns = {
	"ni", "r", "ti", "kim", "gim", "dkss", "sha", "ho", "go", "kyo",
	"nihongo", "aoi", "ue", "an", "han", "hak", "gkr", "seoul", "annyeo",
	"ti\x01", "ti\x02", "ti\x04", "dkss\x04", "nih",
	".", ",", "-", "?", "!", "[", "]", "a.", "ni,", "ho.", "dk,", "t-",
}

-- Strict comparison: both sides scan left-to-right non-overlapping, so
-- the span sequences must be identical item by item.
local fails = 0
for _, p in ipairs(patterns) do
	local vs = vim_spans(p)
	local rs = rust_spans(p)
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
	print(string.format("%-12s spans=%-2d %s", ("%q"):format(p):sub(1, 12), #vs, #vs == #rs and "identical" or "DIFF"))
end
if fails > 0 then error(fails .. " cross-validation failures") end
print("CROSS-VALIDATION PASSED (strict equality)")

-- ---------------------------------------------------------------------------
-- fuzz: random patterns and mixed-CJK lines, vim vs rust must agree
math.randomseed(42) -- deterministic
local alphabet = { "a", "e", "i", "o", "u", "n", "k", "s", "t", "h", "d", "r", "g", "b", "m", "y", "c", "l", "p", "z" }
local soup = {
	"日", "本", "語", "テ", "ス", "ト", "で", "す", "ち", "梯", "子", "韓", "国", "語",
	"安", "녕", "하", "세", "요", "你", "好", "中", "文", "x", "y", "z", "0", "1", " ", " ",
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

local function vim_spans_for(p, ls)
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
			if e0 <= s0 then
				break
			end
		end
	end
	return spans
end

local function rust_spans_for(p, ls)
	local resp = rust.search(p, ls, langs)
	local found = (resp and resp.matches) or {}
	local spans = {}
	for _, m in ipairs(found) do
		spans[#spans + 1] = string.format("%d:%d+%d", m[1] + 1, m[2], m[4])
	end
	return spans
end

local fuzz_fails = 0
for round = 1, 300 do
	local ls, p = { rand_line(), rand_line(), rand_line() }, rand_pattern()
	local vs = vim_spans_for(p, ls)
	local rs = rust_spans_for(p, ls)
	if #vs ~= #rs then
		fuzz_fails = fuzz_fails + 1
		print(string.format("FUZZ COUNT round=%d pattern=%q vim=%d rust=%d", round, p, #vs, #rs))
	else
		for i = 1, #vs do
			if vs[i] ~= rs[i] then
				fuzz_fails = fuzz_fails + 1
				print(string.format("FUZZ SPAN round=%d pattern=%q #%d vim=%s rust=%s", round, p, i, vs[i], rs[i]))
				break
			end
		end
	end
end
if fuzz_fails > 0 then
	error(fuzz_fails .. " fuzz failures")
end
print("FUZZ CROSS-VALIDATION PASSED (300 random rounds, strict equality)")
