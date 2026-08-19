# ADR-0003: Persistent matcher server over a Unix domain socket

- **Status**: accepted (reverses the "persistent daemon" rejection in
  [ADR-0001](./0001-rust-native-matcher.md))
- **Date**: 2026-08-20

## Context

ADR-0001 rejected a daemon because the measured per-keystroke spawn cost
looked like 0.44 ms. The full 15-combination benchmark matrix
(1,050 generated windows, M4 Pro) later showed the real live number:
**9.6 ms mean per keystroke** — ~0.9 ms process creation plus ~8.2 ms
data-table construction that every spawned process repeats. With that
floor the native path loses the entire single-language half of the
matrix to the pure-Lua vim-regex path (0.1–1.0 ms) and only wins on the
heavy mixed tails.

## Decision

Keep the matcher resident: `flash-cjk-search serve --socket <path>` is a
detached, silent Unix domain socket server speaking one NDJSON request
per line per connection. The request envelope gains `pid` (diagnostics)
and `cmd` (`"hello"` registers the connection as a client session,
`"bye"` deregisters it); the response shape is unchanged, so the parity
invariant is untouched.

**Liveness is connection-based, not polled.** A client is registered
exactly while it holds its session connection open; closing it —
normally, on `VimLeavePre`, or by process death, the kernel closes the
fds either way — deregisters it instantly and for free. When the
registry has been empty for the grace period
(`FLASH_CJK_SERVER_GRACE_MS`, default 2000 ms) the server unlinks its
socket and exits: the last Neovim instance out takes the server with it,
absorbing the "B exits, C starts" race. Startup is idempotent (bind
fails but the socket answers → exit 0, a live instance owns it), and a
socket nothing answers (an externally killed server) is reclaimed.

The Lua side (`rust.lua`) owns the socket path (per-user, protocol-
versioned under `XDG_RUNTIME_DIR`/`TMPDIR`), warms the server
asynchronously on the first jump, and falls back per keystroke:
server transport → per-keystroke spawn transport → vim-regex, with the
existing circuit breaker. No new user configuration.

## Alternatives Considered

### pid polling + signal handlers (the original plan sketch)

- Pros: matches the daemon textbook.
- Cons: `kill(pid, 0)` polling and SIGTERM/SIGINT handling need libc FFI
  (new dependency, `unsafe`) or a spawned `/bin/kill` every second
  (battery cost) plus a watchdog child for socket cleanup.
- Why not chosen: open connections already provide exactly this signal —
  EOF on process death — with zero machinery.

### Keep the per-keystroke spawn

- Pros: no lifecycle at all.
- Cons: the 9 ms floor is paid every keystroke of every window; measured
  to make half the matrix slower than pure Lua.

## Consequences

- Rust path drops from 9.60 ms to **1.02 ms mean** per keystroke overall
  (9.4×; p50 8.89 → 0.23 ms, p95 12.8 → 4.3 ms), and now beats vim-regex
  on 13 of 15 categories (the `ko`/`en` singles stay vim-favored at
  sub-0.2 ms either way). UDS round-trip floor: ~0.04 ms.
- One resident process per user (~12.4 MB RSS) exists only while at
  least one Neovim instance has it open; it self-exits within the grace
  period after the last one leaves. No polling, no signals, no config.
- Two transports must behave identically: enforced by the Rust
  integration tests, the run.lua server/spawn parity block, and the
  cross-validation fuzz (which now runs through the server transport).
- Socket paths are capped by `sun_path`; over the cap the transport
  disables itself and keystrokes stay on the spawn path (Windows: always
  spawn path).

## Review Triggers

- Neovim exposes a native way to keep native state resident (then the
  server could move in-process).
- The shared-socket lifetime ever causes user-visible interference
  (revisit per-instance servers).
