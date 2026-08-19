-- LazyVim-style standalone repro for flash-cjk.nvim.
--
-- Modeled on the repro.lua pattern used for LazyVim bug reports: XDG
-- directories are redirected into an isolated root, lazy.nvim is
-- bootstrapped from a stable clone, and flash-cjk is loaded from the
-- local checkout through a real lazy.nvim spec (dir/build/keys/opts).
--
-- Manual use:   nvim -u tests/e2e/repro.lua
-- E2E run:      tests/e2e/run.sh

local uv = vim.uv or vim.loop

local function script_dir()
  local src = debug.getinfo(1, "S").source:sub(2)
  return vim.fs.dirname(vim.fs.normalize(src))
end

local repo_root = vim.fs.dirname(vim.fs.dirname(script_dir()))
repo_root = os.getenv("FLASH_CJK_ROOT") or repo_root

-- Isolated XDG root (mirrors the LazyVim repro pattern).
local root = vim.fs.normalize(os.getenv("FLASH_CJK_E2E_ROOT") or (script_dir() .. "/.repro"))
for _, name in ipairs({ "config", "data", "state", "cache" }) do
  vim.env[("XDG_%s_HOME"):format(name:upper())] = root .. "/" .. name
end

-- Bootstrap a stable lazy.nvim clone inside the repro root.
local lazypath = root .. "/plugins/lazy.nvim"
if not uv.fs_stat(lazypath) then
  local out = vim.fn.system({
    "git",
    "clone",
    "--filter=blob:none",
    "--branch=stable",
    "https://github.com/folke/lazy.nvim.git",
    lazypath,
  })
  if vim.v.shell_error ~= 0 then
    error("failed to clone lazy.nvim:\n" .. out)
  end
end
vim.opt.rtp:prepend(lazypath)

require("lazy").setup({
  spec = {
    {
      "folke/flash.nvim",
      opts = {
        highlight = { backdrop = false, matches = false },
      },
    },
    {
      "flash-cjk.nvim",
      dir = repo_root, -- local checkout; replace with "user/repo" in a bug report
      dependencies = "folke/flash.nvim",
      -- Same build command as documented in README: lazy.nvim runs it as a
      -- shell command in the plugin root on install/update (and via
      -- `:Lazy build`). No cargo => the plugin still works, it just stays
      -- on the vim-regex path.
      build = "cargo build --release --manifest-path=rust/Cargo.toml",
      event = "VeryLazy",
      keys = {
        { "s", mode = { "n", "x", "o" }, function() require("flash-cjk").jump({}) end, desc = "Flash CJK jump" },
      },
      opts = {
        langs = { cn = true, jp = true, ko = true, original = true },
      },
    },
  },
  install = { colorscheme = { "habamax" } },
}, {})

-- When driven by tests/e2e/run.sh, run the scenario right after setup.
if os.getenv("FLASH_CJK_E2E") then
  vim.schedule(function()
    dofile(script_dir() .. "/scenario.lua")
  end)
end
