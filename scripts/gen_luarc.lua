-- Generates .luarc.json for lua-language-server (typecheck task + editors).
-- Written at check time because the Neovim runtime path is machine-specific;
-- the file is gitignored.
--
-- Flash.* annotations need flash.nvim's types. The e2e clone is reused when
-- present and fetched on demand otherwise (same convention as tests/run.lua),
-- so `mise run check` works on a fresh clone.

local flash_dep = ".deps/flash.nvim"
if not vim.uv.fs_stat(flash_dep) then
	vim.fn.mkdir(".deps", "p")
	vim.fn.system({
		"git",
		"clone",
		"--depth",
		"1",
		"https://github.com/folke/flash.nvim",
		flash_dep,
	})
	if vim.v.shell_error ~= 0 then
		error("gen_luarc: failed to clone flash.nvim for type checking")
	end
end

local config = {
	runtime = { version = "LuaJIT" },
	workspace = {
		checkThirdParty = false,
		library = { vim.env.VIMRUNTIME, flash_dep },
		ignoreDir = { ".deps", "rust", "build", "assets", ".git" },
	},
}

local file = assert(io.open(".luarc.json", "w"))
file:write(vim.json.encode(config))
file:close()
