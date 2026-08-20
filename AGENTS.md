# AGENTS.md

Guidance for AI agents working in this repository. Read this before making changes.

flash-cjk.nvim is a Neovim jump plugin (fork of flash-zh.nvim, built on flash.nvim)
that lets users jump to Chinese, Japanese, and Korean characters by typing ASCII
pinyin/romaji/romanization — for people who work in CJK text without switching IMEs.

## Commands

```bash
mise install                 # set up the toolchain (rust, neovim, python+uv, prek, cocogitto, taplo, oxfmt)
mise run check               # fast validation: rustfmt, clippy, markdown/toml formatting — run before every commit
mise run test                # check + cargo test + lua suite + rust/vim parity cross-validation
mise run e2e                 # check + LazyVim-style end-to-end repro (clones .deps on first run)
mise run codegen             # regenerate jaData.lua from Unihan + sync rust data from lua
nvim --headless +"lua dofile('tests/run.lua')" +qa!                # lua suite alone
nvim --headless -l tests/cross_validate_rust.lua                   # parity check alone
cargo build --release --manifest-path rust/Cargo.toml              # native matcher binary
```

Use the targeted single-suite commands while iterating; run `mise run check` before
every commit and the full `mise run test` when touching matcher or labeler logic.

## Engineering Standards

This project follows the shared engineering guidelines:

> https://github.com/fang2hou/ai-coding-guidelines — start from its PORTAL.md.

Read the portal's reading recipes for your task type before starting.
Repository documentation always takes precedence over remembered summaries.

Project-specific overrides:

- The plugin itself is Lua; there is no standardized Lua linter in the shared
  guidelines — match the style of existing modules (EmmyLua annotations, tabs,
  English comments explaining why, not what).
- Rust side: edition 2024, MSRV tracks latest stable (currently 1.97; end
  users build via lazy.nvim `build`), clippy with `-D warnings`, no new
  crates without asking.

## Layout

- `lua/flash-cjk/` — plugin core: `init.lua` (public API and orchestration),
  `config.lua`/`match.lua`/`patches.lua`/`util.lua` (config state, matching
  domain, flash patches, shared helpers), `labeler.lua`, `rust.lua` (native
  matcher bridge with fallback circuit breaker)
- `lua/flash-cjk/lang/` — per-language engines behind one lazy registry
  (`lang/init.lua`, uniform `pattern`/`strs`/`comma` surface): `zhcn.lua`/
  `ja.lua`/`ko.lua` plus their data (`zhcnData.lua`/`zhcnRev.lua`/
  `jaData.lua`, the latter generated); engines load on first use,
  self-checks run only in tests, never in the user's runtime
- `rust/` — optional native matcher: workspace with `flash-cjk-core` (lib) and
  `flash-cjk-search` (stdin/stdout JSON binary); generated data lives in
  `rust/data/` and `flash-cjk-core/src/data/`
- `tests/` — `run.lua` (behavior suite), `cross_validate_rust.lua` (strict rust↔vim-regex parity and fuzz), `e2e/` (LazyVim repro harness)
- `scripts/` — data generators: `gen_jp_data.py` (Unihan → lang/jaData.lua), `export_rs.lua` (lua → rust data)

## Boundaries

Always:

- Run `mise run check` before every commit
- Keep each change minimal and scoped to the request
- When changing matching logic, update both paths (vim-regex in Lua and Rust
  matcher) and keep `tests/cross_validate_rust.lua` green

Never:

- Hand-edit `lua/flash-cjk/lang/jaData.lua` — regenerate with `uv run scripts/gen_jp_data.py`
- Hand-edit generated data (`rust/data/`, `rust/crates/flash-cjk-core/src/data/`) —
  regenerate with `nvim -l scripts/export_rs.lua`
- Change language-lock marker bytes (`\x01/\x02/\x04/\x05`) without updating
  `parse_forced`, the prompt display patch, and the Rust parser together
- Use `pip`/bare `python` — always `uv run` (see mise/python standards)

Ask first:

- New dependencies (cargo crates or anything the Lua side shells out to)
- Changes to invariants in [ARCHITECTURE.md](./ARCHITECTURE.md)
- MSRV / edition changes (they affect every end-user build)

## Confirmed Language Policy

| Item                      | Value                                                                                           |
| ------------------------- | ----------------------------------------------------------------------------------------------- |
| Conversation              | follows the user                                                                                |
| Code / comments / commits | English                                                                                         |
| README                    | English canonical (`README.md`) + `README.zh.md` / `README.ja.md` / `README.ko.md` translations |
| UI strings                | in-prompt lock tags `[中] [日] [韩] [英]` are intentional product strings                       |
| Tone                      | technical, concise                                                                              |

Do not infer UI or doc language from conversation language.

## Project Conventions

- Two matching implementations (vim-regex in Lua, DP in Rust) must stay
  behaviorally identical — `searchpos` semantics, left-to-right, first
  alternative wins, spans never overlap. Cross-validation enforces this.
- Lock markers live in the pattern string as control bytes, decoupled from the
  keys that trigger them; the prompt shows readable tags via a display-only patch.
- Segmentation is capped (`MAX_SEGMENTATIONS`); long inputs degrade gracefully.
- `mise run codegen` is the only way data files change.

Depth: [DEVELOPMENT.md](./DEVELOPMENT.md) for workflow and toolchain, [CONTRIBUTING.md](./CONTRIBUTING.md) for PR rules, [ARCHITECTURE.md](./ARCHITECTURE.md) for invariants.
