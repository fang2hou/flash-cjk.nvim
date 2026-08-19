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

# Isolated runtime dir so the e2e server lifecycle is hermetic: the
# persistent server keys its socket off XDG_RUNTIME_DIR. Kept shallow
# (direct mktemp, not nested under $root) to stay under the Unix
# sun_path cap.
tmp_base="${TMPDIR:-/tmp}"
# strip the trailing slash macOS TMPDIR carries: the server normalizes
# its socket path (vim.fs.normalize) and the pgrep probes below must
# match it exactly
export XDG_RUNTIME_DIR="$(mktemp -d "${tmp_base%/}/fcjk-e2e.XXXXXX")"
trap 'rm -rf "$root" "$XDG_RUNTIME_DIR"' EXIT

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
     nvim --headless -u "$here/repro.lua" +"Lazy! build flash-cjk.nvim" +qa \
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
grep "^ok" "$root/rust.out" | grep -v "rust path" | grep -v "nil-opts" | grep -v "server mode" >"$root/rust.ok"
grep "^ok" "$root/luajit.out" | grep -v "rust path" | grep -v "nil-opts" | grep -v "server mode" >"$root/luajit.ok"
if grep -q "^FAIL" "$root/rust.out" "$root/luajit.out" 2>/dev/null; then
  echo "FAIL scenarios contain failures" && fail=1
elif diff "$root/rust.ok" "$root/luajit.ok" >/dev/null; then
  echo "ok both paths identical"
else
  echo "FAIL rust and vim-regex paths diverged" && fail=1
fi

# ---------------------------------------------------------------- phase 4
# lifecycle: two concurrent nvim instances must share ONE server; the
# server survives the first exit and disappears within the grace
# period after the last one
echo "== phase 4: lifecycle (two instances share one server) =="
srv_count() { pgrep -f "flash-cjk-search serve --socket $XDG_RUNTIME_DIR/" | wc -l | tr -d ' '; }
# any server left over from phase 2 must be gone before we start
for _ in $(seq 1 100); do
  [ "$(srv_count)" = "0" ] && break
  sleep 0.05
done
wait_for() { # $1=expected count $2=timeout in 50ms ticks
  i=0
  while [ "$(srv_count)" != "$1" ] && [ "$i" -lt "$2" ]; do sleep 0.05; i=$((i + 1)); done
  [ "$(srv_count)" = "$1" ]
}
FLASH_CJK_E2E_ROOT="$root" FLASH_CJK_ROOT="$repo" \
  nvim --headless -u "$here/repro.lua" \
  +"lua local r=require('flash-cjk.rust'); r.warmup(); vim.wait(20000, function() return vim.uv.fs_stat('$root/b.ready') ~= nil end, 50)" \
  +qa >"$root/a.log" 2>&1 &
inst_a=$!
wait_for 1 100 || { echo "FAIL instance A did not start a server" && fail=1; }
FLASH_CJK_E2E_ROOT="$root" FLASH_CJK_ROOT="$repo" \
  nvim --headless -u "$here/repro.lua" \
  +"lua local r=require('flash-cjk.rust'); r.warmup(); assert(vim.wait(5000, function() return r.server_ready() end, 20), 'B joined the server'); local f=assert(io.open('$root/b.ready', 'w')); f:close(); vim.wait(6000, function() return false end)" \
  +qa >"$root/b.log" 2>&1 &
inst_b=$!
[ "$(srv_count)" = "1" ] && echo "ok instances A and B share one server" || { echo "FAIL B spawned or lost the server ($(srv_count))" && fail=1; }
wait "$inst_a" 2>/dev/null
[ "$(srv_count)" = "1" ] && echo "ok server survives A quitting" || { echo "FAIL server died with A" && fail=1; }
wait "$inst_b" 2>/dev/null
if wait_for 0 100; then
  echo "ok server exited within grace after the last instance"
else
  echo "FAIL server still running after the last instance" && fail=1
fi


[ "$fail" = 0 ] && echo "E2E PASSED" || echo "E2E FAILED"
exit $fail
