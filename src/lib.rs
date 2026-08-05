//! Roc platform host implementation for Roc's direct-symbol host ABI.

#![allow(improper_ctypes_definitions)]

use std::collections::HashMap;
use std::ffi::{c_char, c_void};
use std::io::{Read, Write};
use std::os::fd::AsRawFd;
use std::sync::{
    atomic::{AtomicBool, Ordering},
    mpsc,
};

use crossterm::{cursor, terminal, ExecutableCommand};

mod roc_platform_abi;
use crate::roc_platform_abi::*;

// ---------------------------------------------------------------------------
// Global Roc host context (needed for roc_alloc / roc_dealloc callbacks called
// by Roc-generated code without any explicit context argument).
// ---------------------------------------------------------------------------

static DEBUG_OR_EXPECT_CALLED: AtomicBool = AtomicBool::new(false);
static mut ROC_HOST: *mut RocHost = core::ptr::null_mut();

fn set_roc_host(roc_host: *mut RocHost) {
    unsafe {
        ROC_HOST = roc_host;
    }
}

fn roc_host_ptr() -> *mut RocHost {
    unsafe {
        if ROC_HOST.is_null() {
            eprintln!("roc host error: RocHost not initialized");
            std::process::exit(1);
        }
        ROC_HOST
    }
}

#[no_mangle]
pub extern "C" fn roc_alloc(length: usize, alignment: usize) -> *mut c_void {
    DefaultAllocators::roc_alloc(roc_host_ptr(), length, alignment)
}

#[no_mangle]
pub extern "C" fn roc_dealloc(ptr: *mut c_void, alignment: usize) {
    DefaultAllocators::roc_dealloc(roc_host_ptr(), ptr, alignment);
}

#[no_mangle]
pub extern "C" fn roc_realloc(
    ptr: *mut c_void,
    new_length: usize,
    alignment: usize,
) -> *mut c_void {
    DefaultAllocators::roc_realloc(roc_host_ptr(), ptr, new_length, alignment)
}

#[no_mangle]
pub extern "C" fn roc_dbg(bytes: *const u8, len: usize) {
    DEBUG_OR_EXPECT_CALLED.store(true, Ordering::Release);
    DefaultHandlers::roc_dbg(roc_host_ptr(), bytes, len);
}

#[no_mangle]
pub extern "C" fn roc_expect_failed(bytes: *const u8, len: usize) {
    DEBUG_OR_EXPECT_CALLED.store(true, Ordering::Release);
    DefaultHandlers::roc_expect_failed(roc_host_ptr(), bytes, len);
}

#[no_mangle]
pub extern "C" fn roc_crashed(bytes: *const u8, len: usize) {
    DefaultHandlers::roc_crashed(roc_host_ptr(), bytes, len);
}

// ---------------------------------------------------------------------------
// TCP server
// ---------------------------------------------------------------------------

/// Events produced by listener/reader threads and consumed by the main loop.
enum TcpEvent {
    /// A new client connected.  The `TcpStream` is a writable clone for the main thread.
    Connected(u64, std::net::TcpStream),
    /// A client disconnected or encountered a read error.
    Disconnected(u64),
    /// Bytes received from a client.
    Data(u64, Vec<u8>),
}

/// TCP state owned exclusively by the main loop.
struct TcpState {
    event_rx: mpsc::Receiver<TcpEvent>,
    /// Read end of a Unix notification pipe — polled alongside stdin.
    notify_rx: i32,
    /// Write end of the pipe — written by TCP threads to wake the poll loop.
    /// `i32` is `Copy`, so threads capture this value directly.
    notify_tx: i32,
    /// Writable handle per active connection, keyed by the stream id.
    writers: HashMap<u64, std::net::TcpStream>,
}

impl Drop for TcpState {
    fn drop(&mut self) {
        unsafe {
            libc::close(self.notify_rx);
            libc::close(self.notify_tx);
        }
    }
}

/// Write one byte to the notification pipe to unblock `poll()` in the main loop.
fn pipe_notify(fd: i32) {
    unsafe { libc::write(fd, [0u8].as_ptr() as *const _, 1) };
}

/// Bind a TCP listener and start background threads.
///
/// Returns `None` if the bind fails.
fn start_tcp_server(host: &str, port: u16) -> Option<TcpState> {
    let mut pipe_fds = [0i32; 2];
    if unsafe { libc::pipe(pipe_fds.as_mut_ptr()) } < 0 {
        eprintln!("TCP: pipe() failed");
        return None;
    }
    let notify_rx = pipe_fds[0];
    let notify_tx = pipe_fds[1];

    let (tx, rx) = mpsc::channel::<TcpEvent>();

    let addr = format!("{}:{}", host, port);
    let listener = match std::net::TcpListener::bind(&addr) {
        Ok(l) => l,
        Err(e) => {
            eprintln!("TCP: bind {} failed: {}", addr, e);
            return None;
        }
    };
    eprintln!("TCP server listening on {}", addr);

    // Listener thread — accepts connections and spawns a reader per connection.
    std::thread::spawn(move || {
        let mut next_id: u64 = 0;

        for incoming in listener.incoming() {
            let stream = match incoming {
                Ok(s) => s,
                Err(e) => {
                    eprintln!("TCP: accept error: {}", e);
                    continue;
                }
            };

            let id = next_id;
            next_id += 1;

            // Clone the stream: one handle for writing (kept by main), one for reading.
            let writer = match stream.try_clone() {
                Ok(w) => w,
                Err(e) => {
                    eprintln!("TCP: stream clone failed (id={}): {}", id, e);
                    continue;
                }
            };

            let _ = tx.send(TcpEvent::Connected(id, writer));
            pipe_notify(notify_tx);

            // Reader thread — one per connection.
            let tx2 = tx.clone();
            std::thread::spawn(move || {
                let mut reader = stream;
                let mut buf = vec![0u8; 4096];

                loop {
                    match reader.read(&mut buf) {
                        Ok(0) => {
                            // EOF — peer closed the connection.
                            let _ = tx2.send(TcpEvent::Disconnected(id));
                            pipe_notify(notify_tx);
                            break;
                        }
                        Ok(n) => {
                            let _ = tx2.send(TcpEvent::Data(id, buf[..n].to_vec()));
                            pipe_notify(notify_tx);
                        }
                        Err(e) => {
                            eprintln!("TCP: read error (id={}): {}", id, e);
                            let _ = tx2.send(TcpEvent::Disconnected(id));
                            pipe_notify(notify_tx);
                            break;
                        }
                    }
                }
            });
        }
    });

    Some(TcpState {
        event_rx: rx,
        notify_rx,
        notify_tx,
        writers: HashMap::new(),
    })
}

/// Connect to a remote TCP host and start a reader thread.
///
/// Returns `None` if the connection fails.
fn start_tcp_client(address: &str, port: u16) -> Option<TcpState> {
    let mut pipe_fds = [0i32; 2];
    if unsafe { libc::pipe(pipe_fds.as_mut_ptr()) } < 0 {
        eprintln!("TCP: pipe() failed");
        return None;
    }
    let notify_rx = pipe_fds[0];
    let notify_tx = pipe_fds[1];

    let (tx, rx) = mpsc::channel::<TcpEvent>();

    let addr = format!("{}:{}", address, port);
    let stream = match std::net::TcpStream::connect(&addr) {
        Ok(s) => s,
        Err(e) => {
            eprintln!("TCP: connect {} failed: {}", addr, e);
            return None;
        }
    };
    eprintln!("TCP client connected to {}", addr);

    let id: u64 = 0; // Client connections always use ID 0 for simplicity

    // Clone the stream: one handle for writing (kept by main), one for reading.
    let writer = match stream.try_clone() {
        Ok(w) => w,
        Err(e) => {
            eprintln!("TCP: stream clone failed: {}", e);
            return None;
        }
    };

    let _ = tx.send(TcpEvent::Connected(id, writer));
    pipe_notify(notify_tx);

    // Reader thread for the connection.
    std::thread::spawn(move || {
        let mut reader = stream;
        let mut buf = vec![0u8; 4096];

        loop {
            match reader.read(&mut buf) {
                Ok(0) => {
                    // EOF — server closed the connection.
                    let _ = tx.send(TcpEvent::Disconnected(id));
                    pipe_notify(notify_tx);
                    break;
                }
                Ok(n) => {
                    let _ = tx.send(TcpEvent::Data(id, buf[..n].to_vec()));
                    pipe_notify(notify_tx);
                }
                Err(e) => {
                    eprintln!("TCP: read error: {}", e);
                    let _ = tx.send(TcpEvent::Disconnected(id));
                    pipe_notify(notify_tx);
                    break;
                }
            }
        }
    });

    Some(TcpState {
        event_rx: rx,
        notify_rx,
        notify_tx,
        writers: HashMap::new(),
    })
}

// ---------------------------------------------------------------------------
// Time utilities
// ---------------------------------------------------------------------------

/// Get the current time as nanoseconds since UNIX epoch (truncated to U64)
fn get_current_time_nanos() -> u64 {
    use std::time::{SystemTime, UNIX_EPOCH};
    match SystemTime::now().duration_since(UNIX_EPOCH) {
        Ok(duration) => duration.as_nanos() as u64, // Truncate to U64 due to compiler bug with U128
        Err(_) => 0, // Should not happen unless system clock is before 1970
    }
}

/// Create a Context with the current time
fn make_context() -> Context {
    Context {
        now_nanos: get_current_time_nanos(),
    }
}

// ---------------------------------------------------------------------------
// Entry point
// ---------------------------------------------------------------------------

#[cfg(not(test))]
#[no_mangle]
pub extern "C" fn main(argc: i32, argv: *const *const c_char) -> i32 {
    rust_main(argc, argv).unwrap()
}

pub fn rust_main(_argc: i32, _argv: *const *const c_char) -> std::io::Result<i32> {
    let mut roc_host = make_roc_host(core::ptr::null_mut());
    set_roc_host(&mut roc_host);

    let mut stdout = std::io::stdout();
    _ = stdout.execute(terminal::EnterAlternateScreen);
    _ = terminal::enable_raw_mode();
    _ = stdout.execute(terminal::Clear(terminal::ClearType::All));

    let (columns, rows) = terminal::size().unwrap();
    let terminal_settings = TerminalSettings {
        width: columns as u64,
        height: rows as u64,
    };

    let ctx = make_context();
    let result = unsafe { roc_init(ctx, RocList::<RocStr>::empty()) };
    let init_effects = result.effects;
    let mut current_model = result.m;
    let mut current_subs = result.sub;

    // Start TCP server once, based on the init subscription.
    // TODO: subscription changes after init (start/stop TCP) are not propagated.
    let mut tcp = init_tcp_from_subs(&current_subs);

    if let Some(code) = handle_effects(init_effects.as_slice(), &mut tcp, &roc_host) {
        cleanup_terminal(&mut stdout);
        return Ok(code as i32);
    }

    loop {
        // `roc_view` calls `Box.unbox` on the model, so incref first to keep a
        // live reference for the subsequent `roc_update` call.
        unsafe { incref_box(current_model, 1) };

        let view_result = unsafe { roc_view(terminal_settings, current_model) };
        match view_result.tag {
            ViewForHostResultTag::Ok => {
                _ = stdout.execute(terminal::Clear(terminal::ClearType::All));
                _ = stdout.execute(cursor::MoveTo(0, 0));
                let rows = unsafe { view_result.payload.ok };
                for row in rows.as_slice() {
                    _ = write!(stdout, "{}", row.as_str());
                    _ = stdout.execute(cursor::MoveToNextLine(1));
                }
            }
            ViewForHostResultTag::Err => {}
        }

        let event = match wait_for_next_event(&current_subs, &mut tcp, &roc_host) {
            Some(e) => e,
            None => {
                cleanup_terminal(&mut stdout);
                return Ok(2);
            }
        };

        let ctx = make_context();
        let update_result = unsafe { roc_update(ctx, current_model, event) };
        if let Some(code) = handle_effects(update_result.effects.as_slice(), &mut tcp, &roc_host) {
            cleanup_terminal(&mut stdout);
            return Ok(code as i32);
        }
        current_model = update_result.m;
        current_subs = update_result.sub;
    }
}

/// Read the `accept_tcp_connection` or `tcp_connect` subscription and start the server/client.
/// Priority: accept_tcp_connection takes precedence over tcp_connect if both are present.
fn init_tcp_from_subs(subs: &Subscriptions) -> Option<TcpState> {
    // Try accept_tcp_connection first (server mode)
    match subs.accept_tcp_connection.tag {
        SubscriptionsAcceptTcpConnectionResultTag::Ok => {
            let p = subs.accept_tcp_connection.payload_ok();
            let host = p.host.as_str().to_owned();
            let port = p.port;
            return start_tcp_server(&host, port);
        }
        SubscriptionsAcceptTcpConnectionResultTag::Err => {}
    }

    // Try tcp_connect (client mode)
    match subs.tcp_connect.tag {
        TryType50Tag::Ok => {
            let p = subs.tcp_connect.payload_ok();
            let address = p.address.as_str().to_owned();
            let port = p.port;
            return start_tcp_client(&address, port);
        }
        TryType50Tag::Err => {}
    }

    None
}

// ---------------------------------------------------------------------------
// Event waiting — multiplexes stdin and the TCP notification pipe via poll()
// ---------------------------------------------------------------------------

fn wait_for_next_event(
    subs: &Subscriptions,
    tcp: &mut Option<TcpState>,
    roc_host: &RocHost,
) -> Option<*mut c_void> {
    let has_stdin = matches!(subs.stdin.tag, SubscriptionsStdinResultTag::Ok);
    let has_tcp = tcp.is_some();
    let has_timer = matches!(subs.timer.tag, SubscriptionsTimerResultTag::Ok);

    if !has_stdin && !has_tcp && !has_timer {
        return None;
    }

    let stdin = std::io::stdin();
    let stdin_fd = stdin.as_raw_fd();

    // Build the poll-fd array.  stdin is always index 0 (if present).
    let mut poll_fds: Vec<libc::pollfd> = Vec::new();
    if has_stdin {
        poll_fds.push(libc::pollfd {
            fd: stdin_fd,
            events: libc::POLLIN,
            revents: 0,
        });
    }
    if let Some(ref t) = tcp {
        poll_fds.push(libc::pollfd {
            fd: t.notify_rx,
            events: libc::POLLIN,
            revents: 0,
        });
    }

    // Index of the TCP pipe fd in poll_fds.
    let tcp_fd_idx = if has_stdin { 1 } else { 0 };

    loop {
        // Check if timer has fired
        if has_timer {
            let timer_payload = unsafe { subs.timer.payload.ok };
            let fire_at = timer_payload.fire_at;
            let now = get_current_time_nanos();
            if now >= fire_at {
                return timer_fire_event(subs);
            }
        }

        // Calculate timeout for poll: if timer is active, poll with timeout
        let timeout_ms = if has_timer {
            let timer_payload = unsafe { subs.timer.payload.ok };
            let fire_at = timer_payload.fire_at;
            let now = get_current_time_nanos();
            if now >= fire_at {
                0 // Timer already fired
            } else {
                let delta_nanos = fire_at - now;
                let delta_ms = (delta_nanos / 1_000_000).min(i32::MAX as u64) as i32;
                delta_ms
            }
        } else {
            -1 // Infinite timeout
        };

        let ret = unsafe { libc::poll(poll_fds.as_mut_ptr(), poll_fds.len() as _, timeout_ms) };
        if ret < 0 {
            return None;
        }

        // --- Timer timeout ---
        if ret == 0 && has_timer {
            // Poll timed out, which means timer should fire
            return timer_fire_event(subs);
        }

        // --- TCP notification pipe ---
        if has_tcp
            && poll_fds
                .get(tcp_fd_idx)
                .map_or(false, |f| f.revents & libc::POLLIN != 0)
        {
            let tcp_state = tcp.as_mut().unwrap();

            // Drain exactly one notification byte (one event was queued per byte).
            let mut byte = [0u8; 1];
            unsafe { libc::read(tcp_state.notify_rx, byte.as_mut_ptr() as _, 1) };

            if let Ok(ev) = tcp_state.event_rx.try_recv() {
                let roc_event = match ev {
                    TcpEvent::Connected(id, writer) => {
                        tcp_state.writers.insert(id, writer);
                        tcp_connected_roc_event(subs, id)
                    }
                    TcpEvent::Disconnected(id) => {
                        tcp_state.writers.remove(&id);
                        tcp_disconnected_roc_event(subs, id)
                    }
                    TcpEvent::Data(id, data) => tcp_receive_roc_event(subs, id, &data, roc_host),
                };
                if let Some(event) = roc_event {
                    return Some(event);
                }
            }

            // No usable event (e.g. subscription says Err) — reset and re-poll.
            if let Some(f) = poll_fds.get_mut(tcp_fd_idx) {
                f.revents = 0;
            }
            continue;
        }

        // --- Stdin ---
        if has_stdin && poll_fds[0].revents & libc::POLLIN != 0 {
            let closure = unsafe { core::mem::ManuallyDrop::into_inner(subs.stdin.payload.ok) };
            const BUF_SIZE: usize = 16_384;
            let mut buffer = [0u8; BUF_SIZE];
            match stdin.lock().read(&mut buffer) {
                Ok(n) if n > 0 => {
                    let data =
                        unsafe { RocListWith::<u8, false>::from_slice(&buffer[..n], roc_host) };
                    return Some(unsafe { make_event_from_list_u8(closure, data) });
                }
                _ => {}
            }
            poll_fds[0].revents = 0;
        }
    }
}

fn tcp_connected_roc_event(subs: &Subscriptions, id: u64) -> Option<*mut c_void> {
    // Try accept_tcp_connection first (server mode)
    match subs.accept_tcp_connection.tag {
        SubscriptionsAcceptTcpConnectionResultTag::Ok => {
            let p = subs.accept_tcp_connection.payload_ok();
            return Some(unsafe { make_event_from_tcp_connected(p.on_connected, id) });
        }
        SubscriptionsAcceptTcpConnectionResultTag::Err => {}
    }

    // Try tcp_connect (client mode)
    match subs.tcp_connect.tag {
        TryType50Tag::Ok => {
            let p = subs.tcp_connect.payload_ok();
            return Some(unsafe { make_event_from_tcp_connected(p.on_connected, id) });
        }
        TryType50Tag::Err => {}
    }

    None
}

fn tcp_disconnected_roc_event(subs: &Subscriptions, id: u64) -> Option<*mut c_void> {
    // Try accept_tcp_connection first (server mode)
    match subs.accept_tcp_connection.tag {
        SubscriptionsAcceptTcpConnectionResultTag::Ok => {
            let p = subs.accept_tcp_connection.payload_ok();
            return Some(unsafe { make_event_from_tcp_disconnected(p.on_disconnected, id) });
        }
        SubscriptionsAcceptTcpConnectionResultTag::Err => {}
    }

    // Try tcp_connect (client mode)
    match subs.tcp_connect.tag {
        TryType50Tag::Ok => {
            let p = subs.tcp_connect.payload_ok();
            return Some(unsafe { make_event_from_tcp_disconnected(p.on_disconnected, id) });
        }
        TryType50Tag::Err => {}
    }

    None
}

fn tcp_receive_roc_event(
    subs: &Subscriptions,
    id: u64,
    data: &[u8],
    roc_host: &RocHost,
) -> Option<*mut c_void> {
    match subs.tcp_receive.tag {
        SubscriptionsTcpReceiveResultTag::Ok => {
            let closure = subs.tcp_receive.payload_ok();
            // Ownership of roc_data is transferred to Roc — no decref needed here.
            let roc_data = unsafe { RocListWith::<u8, false>::from_slice(data, roc_host) };
            Some(unsafe { make_event_from_tcp_receive(closure, id, roc_data) })
        }
        SubscriptionsTcpReceiveResultTag::Err => None,
    }
}

fn timer_fire_event(subs: &Subscriptions) -> Option<*mut c_void> {
    match subs.timer.tag {
        SubscriptionsTimerResultTag::Ok => {
            let timer_payload = unsafe { subs.timer.payload.ok };
            Some(timer_payload.on_fire)
        }
        SubscriptionsTimerResultTag::Err => None,
    }
}

// ---------------------------------------------------------------------------
// Effect handling
// ---------------------------------------------------------------------------

fn cleanup_terminal(stdout: &mut std::io::Stdout) {
    let _ = terminal::disable_raw_mode();
    let _ = stdout.execute(terminal::LeaveAlternateScreen);
}

/// Process effects. Returns `Some(exit_code)` if an `Exit` effect was encountered.
fn handle_effects(
    effects: &[Effect],
    tcp: &mut Option<TcpState>,
    roc_host: &RocHost,
) -> Option<u16> {
    for effect in effects {
        match effect.tag {
            EffectTag::Exit => {
                return Some(unsafe { *effect.payload.exit });
            }
            EffectTag::Print => {
                let text = unsafe { *effect.payload.print };
                println!("Print: {}", text.as_str());
            }
            EffectTag::WriteToFile => {
                let p = unsafe { effect.payload.write_to_file };
                println!(
                    "WriteToFile: filename={} content={}",
                    p.filename.as_str(),
                    p.content.as_str()
                );
            }
            EffectTag::TcpSend => {
                let payload = effect.payload_tcp_send();
                let stream_id = payload.stream.id;

                if let Some(ref mut tcp_state) = tcp {
                    if let Some(writer) = tcp_state.writers.get_mut(&stream_id) {
                        if let Err(e) = writer.write_all(payload.data.as_slice()) {
                            eprintln!("TCP: send error (id={}): {}", stream_id, e);
                            // The reader thread will also send a Disconnected event,
                            // but remove here too to stop further failed writes.
                            tcp_state.writers.remove(&stream_id);
                        }
                    }
                }

                // payload_tcp_send() used ManuallyDrop::into_inner, so we own this
                // copy and must decrement both fields (stream.id is a no-op, data
                // is a heap-allocated Roc list).
                unsafe { payload.decref(roc_host) };
            }
        }
    }
    None
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    #[test]
    fn placeholder() {
        assert!(1 == 1);
    }
}
