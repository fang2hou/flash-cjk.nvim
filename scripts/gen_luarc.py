#!/usr/bin/env python3
# /// script
# requires-python = ">=3.14"
# dependencies = []
# ///
"""Generate .luarc.json for lua-language-server (typecheck task + editors).

Written at check time because the Neovim runtime path is machine-specific;
the file is gitignored.
"""

from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

def nvim_runtime() -> str:
    # :lua print() goes to stderr in headless mode; io.write() goes to stdout
    result = subprocess.run(
        ["nvim", "--headless", "-c", 'lua io.write(vim.env.VIMRUNTIME or "")', "-c", "qa!"],
        capture_output=True,
        text=True,
    )
    runtime = result.stdout.strip()
    if not runtime:
        sys.exit("gen_luarc: could not resolve $VIMRUNTIME from nvim")
    return runtime


config = {
    "runtime": {"version": "LuaJIT"},
    "workspace": {
        "checkThirdParty": False,
        "library": [nvim_runtime()],
        "ignoreDir": [".deps", "rust", "build", "assets", ".git"],
    },
}

# Flash.* annotations resolve when the e2e flash.nvim clone is present.
if (ROOT / ".deps/flash.nvim").exists():
    config["workspace"]["library"].append(".deps/flash.nvim")

(ROOT / ".luarc.json").write_text(json.dumps(config), encoding="utf-8")
