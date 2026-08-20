-- Generates .luarc.json for lua-language-server (typecheck task + editors).
-- Written at check time because the Neovim runtime path is machine-specific;
-- the file is gitignored.

local config = {
	runtime = { version = "LuaJIT" },
	workspace = {
		checkThirdParty = false,
		library = { vim.env.VIMRUNTIME },
		ignoreDir = { ".deps", "rust", "build", "assets", ".git" },
	},
}

-- Flash.* annotations resolve when the e2e flash.nvim clone is present.
if vim.uv.fs_stat(".deps/flash.nvim") then
	table.insert(config.workspace.library, ".deps/flash.nvim")
end

local file = assert(io.open(".luarc.json", "w"))
file:write(vim.json.encode(config))
file:close()
