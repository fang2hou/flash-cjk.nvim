//! Persistent serve mode: one Unix domain socket, NDJSON requests.
//!
//! Lifecycle contract (connection-based liveness, ADR-0003): the client
//! registry is the set of open *session* connections. A client opens
//! one session connection on first contact (`{"cmd":"hello","pid":N}`)
//! and holds it open for its lifetime; closing it — normally or by
//! process death, the kernel closes the file descriptors either way —
//! deregisters the client. `{"cmd":"bye","pid":N}` is the fast path
//! for a clean exit. The `pid` field is diagnostics only.
//!
//! When the registry has been continuously empty longer than the grace
//! period (`FLASH_CJK_SERVER_GRACE_MS`, default 2000 ms) the server
//! unlinks its socket and exits: the last Neovim instance out takes
//! the server with it, without any signal handling or polling.
//!
//! Startup is idempotent: binding fails but the socket still accepts
//! connections means another live instance owns it — exit 0 without
//! touching anything. A socket file that nothing answers (a server
//! killed externally) is reclaimed: unlinked and rebound.

use std::collections::HashMap;
use std::fs::{File, OpenOptions};
use std::io::{BufRead, BufReader, Write};
use std::os::unix::net::{UnixListener, UnixStream};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Condvar, Mutex};
use std::thread;
use std::time::{Duration, Instant};

use anyhow::{Context, Result};
use serde::Deserialize;

use crate::{LangsSpec, Response, answer};

/// How the serve entry point ended.
enum Outcome {
    /// Registry stayed empty past the grace period; socket unlinked.
    Exited,
    /// A live instance already owns the socket; nothing was touched.
    AlreadyRunning,
}

/// The serve request envelope: a search request plus the session
/// commands. Absent `pattern`/`lines` only occur on `cmd` requests;
/// `langs` mirrors the one-shot protocol defaults.
#[derive(Deserialize, Default)]
#[serde(default)]
struct Envelope {
    pattern: Option<String>,
    lines: Option<Vec<String>>,
    langs: LangsSpec,
    /// client process id, logged for diagnostics only
    pid: Option<u32>,
    /// "hello" registers this connection as a client session;
    /// "bye" deregisters it and closes the connection
    cmd: Option<String>,
}

struct Registry {
    /// session connection id -> client pid (diagnostics only)
    sessions: HashMap<u64, u32>,
    /// when the registry last became empty; None while clients exist.
    /// The server starts empty, so a server nobody ever contacts exits
    /// after one grace period.
    empty_since: Option<Instant>,
}

/// Mutex and condvar live side by side so the monitor can hand the
/// guard back and forth with `wait`/`wait_timeout`.
struct RegistryLock {
    reg: Mutex<Registry>,
    changed: Condvar,
}
struct Shared {
    reg: RegistryLock,
    log: Mutex<Option<File>>,
    started: Instant,
}

impl RegistryLock {
    fn new() -> Self {
        RegistryLock {
            reg: Mutex::new(Registry {
                sessions: HashMap::new(),
                empty_since: Some(Instant::now()),
            }),
            changed: Condvar::new(),
        }
    }

    fn register(&self, id: u64, pid: u32) {
        let mut reg = self.reg.lock().unwrap();
        reg.sessions.insert(id, pid);
        reg.empty_since = None;
        self.changed.notify_all();
    }

    fn deregister(&self, id: u64) {
        let mut reg = self.reg.lock().unwrap();
        if reg.sessions.remove(&id).is_some() && reg.sessions.is_empty() {
            reg.empty_since.get_or_insert_with(Instant::now);
        }
        self.changed.notify_all();
    }
}

impl Shared {
    fn log(&self, msg: &str) {
        let mut guard = self.log.lock().unwrap();
        if let Some(f) = guard.as_mut() {
            let _ = writeln!(f, "[{:>9.3}] {}", self.started.elapsed().as_secs_f64(), msg);
        }
    }
}

/// Parses `serve [--socket <path>] [--log <path>]` and runs the server.
pub fn main(args: &[String]) -> Result<()> {
    let mut socket: Option<PathBuf> = None;
    let mut log_path: Option<PathBuf> = None;
    let mut it = args.iter();
    while let Some(arg) = it.next() {
        match arg.as_str() {
            "--socket" => {
                socket = Some(PathBuf::from(
                    it.next().context("--socket requires a path")?,
                ));
            }
            "--log" => {
                log_path = Some(PathBuf::from(it.next().context("--log requires a path")?));
            }
            other => anyhow::bail!("unknown serve argument: {other}"),
        }
    }
    let socket = socket.context("serve requires --socket <path>")?;
    let grace_ms: u64 = std::env::var("FLASH_CJK_SERVER_GRACE_MS")
        .ok()
        .and_then(|v| v.parse().ok())
        .unwrap_or(2000)
        .max(1);
    serve(socket, log_path, Duration::from_millis(grace_ms))?;
    Ok(())
}

fn serve(socket: PathBuf, log_path: Option<PathBuf>, grace: Duration) -> Result<Outcome> {
    let log_file = match &log_path {
        Some(p) => Some(
            OpenOptions::new()
                .create(true)
                .append(true)
                .open(p)
                .with_context(|| format!("opening log file {}", p.display()))?,
        ),
        None => None,
    };
    let listener = match bind(&socket)? {
        Some(l) => l,
        None => return Ok(Outcome::AlreadyRunning),
    };
    // pay the data-table startup exactly once, before the first request
    warm_tables();
    let shared = Arc::new(Shared {
        reg: RegistryLock::new(),
        log: Mutex::new(log_file),
        started: Instant::now(),
    });
    shared.log(&format!(
        "serve start socket={} grace_ms={} pid={}",
        socket.display(),
        grace.as_millis(),
        std::process::id()
    ));
    {
        let shared = Arc::clone(&shared);
        let socket = socket.clone();
        thread::spawn(move || monitor(shared, socket, grace));
    }
    let next_id = AtomicU64::new(1);
    for conn in listener.incoming() {
        let Ok(stream) = conn else { continue };
        let shared = Arc::clone(&shared);
        let id = next_id.fetch_add(1, Ordering::Relaxed);
        thread::spawn(move || {
            if let Err(e) = handle_conn(stream, id, &shared) {
                shared.log(&format!("conn {id}: {e:#}"));
            }
        });
    }
    Ok(Outcome::Exited)
}

/// Binds the socket, reclaiming a stale one (file present, nothing
/// answering) and deferring to a live instance (exit via `None`).
fn bind(socket: &Path) -> Result<Option<UnixListener>> {
    match UnixListener::bind(socket) {
        Ok(l) => Ok(Some(l)),
        Err(e) if e.kind() == std::io::ErrorKind::AddrInUse => {
            if UnixStream::connect(socket).is_ok() {
                return Ok(None);
            }
            std::fs::remove_file(socket)
                .with_context(|| format!("removing stale socket {}", socket.display()))?;
            UnixListener::bind(socket)
                .with_context(|| format!("rebinding socket {}", socket.display()))
                .map(Some)
        }
        Err(e) => {
            Err(anyhow::Error::new(e).context(format!("binding socket {}", socket.display())))
        }
    }
}

/// Forces the core's lazy table construction so the cost lands here,
/// once, instead of on the first request.
fn warm_tables() {
    let _ = flash_cjk_core::data::data();
    let _ = &flash_cjk_core::data::CN_REVERSE;
}

/// Owns the self-exit decision: wake on every registry change; exit
/// once the registry has been empty for the whole grace period.
fn monitor(shared: Arc<Shared>, socket: PathBuf, grace: Duration) {
    let mut reg = shared.reg.reg.lock().unwrap();
    loop {
        if reg.sessions.is_empty() {
            let deadline = reg.empty_since.unwrap_or_else(Instant::now) + grace;
            let now = Instant::now();
            if now >= deadline {
                break;
            }
            let (guard, _) = shared
                .reg
                .changed
                .wait_timeout(reg, deadline - now)
                .unwrap();
            reg = guard;
        } else {
            reg.empty_since = None;
            let guard = shared.reg.changed.wait(reg).unwrap();
            reg = guard;
        }
    }
    drop(reg);
    shared.log("exit: no clients beyond the grace period");
    let _ = std::fs::remove_file(&socket);
    std::process::exit(0);
}

/// Handles one connection; the session registration is released on
/// EVERY exit path (an errored write to an already-closed client must
/// not leak the registry entry, or the server would never self-exit).
fn handle_conn(stream: UnixStream, id: u64, shared: &Shared) -> Result<()> {
    let writer = stream.try_clone().context("cloning connection stream")?;
    let reader = BufReader::new(stream);
    let mut session = false;
    let res = conn_loop(reader, writer, id, shared, &mut session);
    if session {
        shared.reg.deregister(id);
        shared.log(&format!("conn {id}: closed"));
    }
    res
}

fn conn_loop(
    reader: BufReader<UnixStream>,
    mut writer: UnixStream,
    id: u64,
    shared: &Shared,
    session: &mut bool,
) -> Result<()> {
    for line in reader.lines() {
        let line = match line {
            Ok(l) => l,
            Err(_) => break, // connection reset: same as closed below
        };
        if line.trim().is_empty() {
            continue;
        }
        let env: Envelope = match serde_json::from_str(&line) {
            Ok(e) => e,
            Err(e) => {
                shared.log(&format!("conn {id}: bad request: {e}"));
                let msg = serde_json::to_string(&format!("{e}")).unwrap_or_else(|_| "\"?\"".into());
                writeln!(writer, "{{\"error\":{msg}}}")?;
                break;
            }
        };
        match env.cmd.as_deref() {
            Some("hello") => {
                *session = true;
                shared.reg.register(id, env.pid.unwrap_or(0));
                shared.log(&format!("conn {id}: hello pid={}", env.pid.unwrap_or(0)));
                writeln!(writer, "{{\"ok\":true}}")?;
                writer.flush().ok();
            }
            Some("bye") => {
                shared.log(&format!("conn {id}: bye pid={}", env.pid.unwrap_or(0)));
                writeln!(writer, "{{\"ok\":true}}")?;
                writer.flush().ok();
                break; // closing deregisters below
            }
            Some(other) => {
                shared.log(&format!("conn {id}: unknown cmd {other}"));
                let msg = serde_json::to_string(other).unwrap_or_else(|_| "\"?\"".into());
                writeln!(writer, "{{\"error\":\"unknown cmd\":{msg}}}")?;
                break;
            }
            None => {
                let pattern = env.pattern.unwrap_or_default();
                let lines = env.lines.unwrap_or_default();
                let resp = answer(&pattern, &lines, env.langs.into());
                write_response(&mut writer, &resp)?;
            }
        }
    }
    Ok(())
}

fn write_response(w: &mut UnixStream, resp: &Response) -> Result<()> {
    let mut json = serde_json::to_string(resp).context("encoding response")?;
    json.push('\n');
    w.write_all(json.as_bytes()).context("writing response")?;
    Ok(())
}
