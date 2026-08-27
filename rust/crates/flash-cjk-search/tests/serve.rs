//! Integration tests for the persistent serve mode: request transport,
//! connection-based client lifecycle, and socket lifecycle rules.
//!
//! A "client" is a held-open session connection (`{"cmd":"hello"}`):
//! closing it — by drop or by process death, the kernel closes the
//! file descriptors either way — deregisters the client, and the
//! server exits once its registry has been empty for the grace period
//! (`FLASH_CJK_SERVER_GRACE_MS`, shrunk per test).

#![cfg(unix)]

use std::io::{BufRead, BufReader, Write};
use std::os::unix::net::{UnixListener, UnixStream};
use std::path::{Path, PathBuf};
use std::process::{Child, Command, Stdio};
use std::sync::atomic::{AtomicU64, Ordering};
use std::thread;
use std::time::{Duration, Instant};

use serde_json::{Value, json};

static COUNTER: AtomicU64 = AtomicU64::new(0);

struct Server {
    child: Child,
    socket: PathBuf,
}

impl Drop for Server {
    fn drop(&mut self) {
        let _ = self.child.kill();
        let _ = self.child.wait();
    }
}

fn temp_socket() -> PathBuf {
    let dir = std::env::temp_dir().join(format!(
        "fcjk-serve-test-{}-{}",
        std::process::id(),
        COUNTER.fetch_add(1, Ordering::Relaxed)
    ));
    std::fs::create_dir_all(&dir).unwrap();
    dir.join("server.sock")
}

fn spawn_server(socket: &Path, grace_ms: u64) -> Child {
    Command::new(env!("CARGO_BIN_EXE_flash-cjk-search"))
        .arg("serve")
        .arg("--socket")
        .arg(socket)
        .env("FLASH_CJK_SERVER_GRACE_MS", grace_ms.to_string())
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()
        .expect("spawning flash-cjk-search serve")
}

/// Starts a server and waits until its socket accepts connections.
fn start_server(grace_ms: u64) -> Server {
    let socket = temp_socket();
    let child = spawn_server(&socket, grace_ms);
    let server = Server { child, socket };
    wait_connectable(&server.socket, Duration::from_secs(5));
    server
}

fn wait_connectable(socket: &Path, within: Duration) -> UnixStream {
    let deadline = Instant::now() + within;
    loop {
        match UnixStream::connect(socket) {
            Ok(s) => return s,
            Err(_) if Instant::now() < deadline => thread::sleep(Duration::from_millis(20)),
            Err(e) => panic!("server never came up at {}: {e}", socket.display()),
        }
    }
}

/// Sends one NDJSON line and reads one response line.
fn rpc(stream: &mut UnixStream, payload: &Value) -> Value {
    let mut line = payload.to_string();
    line.push('\n');
    stream.write_all(line.as_bytes()).unwrap();
    stream.flush().unwrap();
    let mut reader = BufReader::new(stream.try_clone().unwrap());
    let mut resp = String::new();
    reader.read_line(&mut resp).unwrap();
    assert!(!resp.is_empty(), "server closed without a response");
    serde_json::from_str(resp.trim()).expect("response is valid JSON")
}

/// Opens a session connection and keeps it open: a registered client.
fn hello_stream(socket: &Path, pid: u32) -> UnixStream {
    let mut s = UnixStream::connect(socket).unwrap();
    let resp = rpc(&mut s, &json!({"cmd": "hello", "pid": pid}));
    assert_eq!(resp, json!({"ok": true}));
    s
}

/// Polls `try_wait` until the child exits or the deadline passes.
fn exited(child: &mut Child, within: Duration) -> Option<std::process::ExitStatus> {
    let deadline = Instant::now() + within;
    loop {
        if let Some(status) = child.try_wait().unwrap() {
            return Some(status);
        }
        if Instant::now() >= deadline {
            return None;
        }
        thread::sleep(Duration::from_millis(20));
    }
}

/// Polls `try_wait` asserting the child stays alive the whole time.
fn stays_alive(child: &mut Child, for_at_least: Duration) {
    let deadline = Instant::now() + for_at_least;
    while Instant::now() < deadline {
        assert!(
            child.try_wait().unwrap().is_none(),
            "server died while a client was registered"
        );
        thread::sleep(Duration::from_millis(20));
    }
}

// -------------------------------------------------------------------------

#[test]
fn search_round_trip() {
    let server = start_server(10_000);
    let lines = ["日本語テスト ち 梯"];

    // per-request connection: the transport a live keystroke uses
    let mut req = UnixStream::connect(&server.socket).unwrap();
    let resp = rpc(
        &mut req,
        &json!({"pattern": "ti", "lines": lines, "langs": {}, "pid": 1}),
    );
    let matches = resp["matches"].as_array().unwrap();
    assert!(!matches.is_empty(), "ti must match the window");
    assert_eq!(resp["predictions"].as_array().unwrap().len(), matches.len());
    assert_eq!(resp["pred_langs"].as_array().unwrap().len(), matches.len());
    // the ja reading of ち and the zhcn reading of 梯 are both found
    let langs: Vec<String> = resp["pred_langs"]
        .as_array()
        .unwrap()
        .iter()
        .flat_map(|v| v.as_array().unwrap().clone())
        .filter_map(|s| s.as_str().map(str::to_string))
        .collect();
    assert!(langs.contains(&"ja".to_string()), "pred_langs: {langs:?}");
    assert!(langs.contains(&"zhcn".to_string()), "pred_langs: {langs:?}");

    // the same search on an open session connection must work too
    let mut session = hello_stream(&server.socket, std::process::id());
    let resp2 = rpc(
        &mut session,
        &json!({"pattern": "ti", "lines": lines, "langs": {}, "pid": 1}),
    );
    assert_eq!(resp2["matches"], resp["matches"]);
    assert_eq!(resp2["pred_langs"], resp["pred_langs"]);
}

#[test]
fn two_clients_last_close_exits_server() {
    let mut server = start_server(300);
    let c1 = hello_stream(&server.socket, 1111);
    let _c2 = hello_stream(&server.socket, 2222);

    // first client disappears (drop closes the fd, exactly what
    // process death does): the second still holds the server open
    drop(c1);
    stays_alive(&mut server.child, Duration::from_millis(600));

    // last client out: exit within the grace period, socket unlinked
    drop(_c2);
    let status = exited(&mut server.child, Duration::from_millis(1500))
        .expect("server must exit within grace after the last client leaves");
    assert!(status.success());
    assert!(!server.socket.exists(), "socket must be unlinked on exit");
}

#[test]
fn bye_deregisters_immediately() {
    let mut server = start_server(300);
    let mut session = hello_stream(&server.socket, 3333);
    let resp = rpc(&mut session, &json!({"cmd": "bye", "pid": 3333}));
    assert_eq!(resp, json!({"ok": true}));

    // bye closed the session: registry empty, grace counts from here
    let status = exited(&mut server.child, Duration::from_millis(1500))
        .expect("server must exit within grace after bye");
    assert!(status.success());
    assert!(!server.socket.exists());
}

#[test]
fn unknown_cmd_replies_valid_json_then_closes() {
    let server = start_server(300);
    let mut stream = hello_stream(&server.socket, 4444);

    // Raw line read: the reply is pinned byte-for-byte. serde_json's
    // Map is a BTreeMap here (no preserve_order feature), so keys
    // serialize alphabetically.
    let mut reader = BufReader::new(stream.try_clone().unwrap());
    stream.write_all(b"{\"cmd\":\"bogus\"}\n").unwrap();
    stream.flush().unwrap();

    let mut line = String::new();
    reader.read_line(&mut line).unwrap();
    assert_eq!(line.trim_end(), r#"{"cmd":"bogus","error":"unknown cmd"}"#);

    // The connection is closed after the reply: EOF, not another line.
    let mut more = String::new();
    assert_eq!(reader.read_line(&mut more).unwrap(), 0);
}

#[test]
fn unused_server_exits_after_grace() {
    let mut server = start_server(300);
    // no session ever opened: the grace period runs from startup
    let status = exited(&mut server.child, Duration::from_millis(2000))
        .expect("a server nobody registers with must self-exit");
    assert!(status.success());
    assert!(!server.socket.exists());
}

#[test]
fn closed_right_after_hello_still_deregisters() {
    // regression: a client that closes without reading the ok can make
    // the server's ok write fail (EPIPE); the session must still be
    // released or the server would never self-exit
    let mut server = start_server(300);
    let mut s = UnixStream::connect(&server.socket).unwrap();
    s.write_all(b"{\"cmd\":\"hello\",\"pid\":7}\n").unwrap();
    s.flush().unwrap();
    drop(s);
    let status = exited(&mut server.child, Duration::from_millis(1500))
        .expect("must exit even when the ok write fails");
    assert!(status.success());
    assert!(!server.socket.exists());
}

#[test]
fn stale_socket_is_reclaimed() {
    let socket = temp_socket();
    // a server killed externally leaves the socket file behind with
    // nothing answering on it
    let ghost = UnixListener::bind(&socket).unwrap();
    drop(ghost);
    assert!(socket.exists());

    let server = Server {
        child: spawn_server(&socket, 10_000),
        socket,
    };
    wait_connectable(&server.socket, Duration::from_secs(5));
    let mut req = UnixStream::connect(&server.socket).unwrap();
    let resp = rpc(
        &mut req,
        &json!({"pattern": "kim", "lines": ["김"], "langs": {}, "pid": 1}),
    );
    assert!(!resp["matches"].as_array().unwrap().is_empty());
}

#[test]
fn second_start_defers_to_live_instance() {
    let server = start_server(10_000);
    let _session = hello_stream(&server.socket, std::process::id());

    let mut second = spawn_server(&server.socket, 10_000);
    let status =
        exited(&mut second, Duration::from_secs(3)).expect("second start must return promptly");
    assert_eq!(status.code(), Some(0), "idempotent start exits 0");

    // the original instance keeps serving untouched
    let mut req = UnixStream::connect(&server.socket).unwrap();
    let resp = rpc(
        &mut req,
        &json!({"pattern": "ti", "lines": ["ち"], "langs": {}, "pid": 1}),
    );
    assert!(!resp["matches"].as_array().unwrap().is_empty());
}
