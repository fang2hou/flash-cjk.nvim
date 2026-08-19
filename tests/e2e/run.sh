#!/bin/sh
# flash-cjk e2e: LazyVim-style repro harness.
#
# Phase 1  nvim -u repro.lua "+Lazy build flash-cjk.nvim"   -> exercises the
#          exact build command documented in README (cargo required).
# Phase 2  scenario with the Rust fast path (binary from phase 1).
# Phase 3  scenario with the Rust path disabled (vim-regex fallback).
# Parity   phase 2 and phase 3 must produce identical results.
#
# Usage: tests/e2e/run.sh          (requires cargo + network on first run)
#        tests/e2e/run.sh --no-build   (skip phase 1; binary must exist)

set -u

here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/../.." && pwd)
root=$(mktemp -d "${TMPDIR:-/tmp}/flash-cjk-e2e.XXXXXX")
trap 'rm -rf "$root"' EXIT

do_build=1
[ "${1:-}" = "--no-build" ] && do_build=0

run_phase() { # $1=out-file $2=no_rust(1|0)
  FLASH_CJK_E2E=1 \
  FLASH_CJK_E2E_ROOT="$root" \
  FLASH_CJK_E2E_OUT="$1" \
  FLASH_CJK_E2E_NO_RUST="$2" \
  FLASH_CJK_ROOT="$repo" \
  nvim --headless -u "$here/repro.lua" >"$root/nvim.log" 2>&1
}

fail=0

if [ "$do_build" = 1 ]; then
  echo "== phase 1: Lazy build (README build command) =="
  if FLASH_CJK_E2E_ROOT="$root" FLASH_CJK_ROOT="$repo" \
     nvim --headless -u "$here/repro.lua" +"Lazy build flash-cjk.nvim" +qa \
     >"$root/build.log" 2>&1 \
     && [ -x "$repo/rust/target/release/flash-cjk-search" ]; then
    echo "ok lazy build: cargo build ran through the lazy.nvim spec"
  else
    echo "FAIL lazy build (see $root/build.log)" && fail=1
  fi
fi

echo "== phase 2: scenario (rust fast path) =="
run_phase "$root/rust.out" ""
[ -s "$root/rust.out" ] || { echo "FAIL phase 2 produced no output (see $root/nvim.log)"; fail=1; }
cat "$root/rust.out"

echo "== phase 3: scenario (vim-regex fallback) =="
run_phase "$root/luajit.out" 1
cat "$root/luajit.out"

echo "== parity: rust vs vim-regex =="
grep "^ok" "$root/rust.out" | grep -v "rust path" | grep -v "nil-opts" >"$root/rust.ok"
grep "^ok" "$root/luajit.out" | grep -v "rust path" | grep -v "nil-opts" >"$root/luajit.ok"
if grep -q "^FAIL" "$root/rust.out" "$root/luajit.out" 2>/dev/null; then
  echo "FAIL scenarios contain failures" && fail=1
elif diff "$root/rust.ok" "$root/luajit.ok" >/dev/null; then
  echo "ok both paths identical"
else
  echo "FAIL rust and vim-regex paths diverged" && fail=1
fi

[ "$fail" = 0 ] && echo "E2E PASSED" || echo "E2E FAILED"
exit $fail
