# Development

How development is performed in this repository, for both humans and AI agents.
User-facing setup lives in the README; this document is for people changing the code.

## Setup

All tools are managed by mise.

```bash
mise install
```

| Tool                | Purpose                                                   | Managed via |
| ------------------- | --------------------------------------------------------- | ----------- |
| rust                | Native matcher toolchain                                  | `mise.toml` |
| neovim              | Test/runtime host                                         | `mise.toml` |
| uv                  | Data generator runner (Python 3.14 via `.python-version`) | `mise.toml` |
| stylua              | Lua formatter                                             | `mise.toml` |
| lua-language-server | Lua type checking                                         | `mise.toml` |
| taplo               | TOML formatter                                            | `mise.toml` |
| oxfmt               | Markdown formatter                                        | `mise.toml` |
| prek                | Pre-commit hooks                                          | `mise.toml` |
| cocogitto           | Conventional Commits verification                         | `mise.toml` |

Do not substitute tools without explicit approval (see the guidelines repository's toolchain standards).

## Commands

```bash
mise run check              # rustfmt + clippy + stylua + lua typecheck + md/toml — what prek and CI run
mise run test               # check + cargo test + lua suite + cross-validation
mise run e2e                # LazyVim-style end-to-end repro (first run clones .deps/)
mise run codegen            # regenerate jp data (Unihan) + sync rust/data from json
mise run format             # format rust, lua, markdown, toml in place
cargo build --release --manifest-path rust/Cargo.toml   # native matcher binary for daily use
```

`mise run` lists every task.

## Workflow

1. Branch from `main`
2. Implement the smallest coherent change
3. `mise run check` must pass; matcher/labeler changes additionally need
   `mise run test` (parity suite)
4. Commit with Conventional Commits (validated by Cocogitto)
5. Open a PR following [CONTRIBUTING.md](./CONTRIBUTING.md)

## Layout

- `lua/flash-cjk/` — plugin core: public API and orchestration (`init.lua`),
  config state (`config.lua`), matching domain (`match.lua`), flash patches,
  labeler, native bridge, language engines under `lang/` (one folder per
  language: `init.lua` engine + `data.json` dictionary)
- `rust/` — optional native matcher (core lib and JSON binary); generated
  data in `rust/data/` and `rust/crates/flash-cjk-core/src/data/`
- `tests/` — behavior suite, rust↔vim strict cross-validation, e2e repro
- `scripts/` — data generators and the typecheck config generator
- `benches/` — benchmark harness + SVG generator

## Coding Standards

Follow the guidelines repository's coding standards. Project-specific rules:

- Lua: StyLua enforces formatting (`stylua.toml`: tabs, 100 cols);
  `mise run typecheck` (lua-language-server) must stay clean — prefer real
  fixes over diagnostic suppressions, and justify every `---@diagnostic`
  line with a comment
- Comments explain _why_, sparingly; names and structure carry the rest.
  EmmyLua annotations on public functions
- Two matching paths must stay behaviorally identical — change both or neither
- Generated files (`lang/ja/data.json`, `rust/data/`) change only via `mise run codegen`
- Rust: edition 2024, MSRV tracks latest stable (currently 1.97), clippy `-D warnings`, no `unsafe`

## Testing

- Rust unit and cross checks: covered by `mise run test` (`cargo test`)
- Lua behavior suite: `nvim --headless +"lua dofile('tests/run.lua')" +qa!`
- Parity: `nvim --headless -l tests/cross_validate_rust.lua` — strict equality
  between the Rust matcher and the vim-regex path, plus 300 fuzz rounds
- E2E: `mise run e2e` — real flash loop through a lazy.nvim load, both paths
- Prioritize meaningful behavior over coverage numbers

## Debugging

- `cargo run --example spell_dbg` (in `rust/`) prints spellings/next-letter
  predictions for a string — useful when the labeler mispredicts
- The e2e harness (`tests/e2e/`) reproduces the real jump loop in isolation;
  `repro.lua` is the minimal LazyVim-style spec it loads
- Native path issues: `require("flash-cjk.rust").disable_for_test()` forces the
  vim-regex path; the circuit breaker trips after 3 consecutive binary failures

## Validation

`mise run check` is the entry point for the project's main validation.
It runs the same checks locally that CI runs — do not maintain separate logic.
The Lua type-check config is generated at check time (`scripts/gen_luarc.lua`
resolves the machine-specific Neovim runtime path); `.luarc.json` is gitignored.
Hooks: `prek install` once; prek then runs `mise run check` and gitleaks on commit.
