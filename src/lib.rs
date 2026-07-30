//! Roc platform host implementation for Roc's direct-symbol host ABI.

#![allow(improper_ctypes_definitions)]

use std::ffi::{c_char, c_void};
use std::io::Read;
use std::io::Write;
use std::os::fd::AsRawFd;

use std::sync::atomic::{AtomicBool, Ordering};

use crossterm::terminal;
use crossterm::ExecutableCommand;

mod roc_platform_abi;

use crate::roc_platform_abi::*;

pub(crate) fn roc_u8_list_from_slice(slice: &[u8], roc_host: &RocHost) -> RocListWith<u8, false> {
    unsafe { RocListWith::<u8, false>::from_slice(slice, roc_host) }
}

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

pub(crate) fn roc_host() -> &'static RocHost {
    unsafe { &*roc_host_ptr() }
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

    use crossterm::{style::Stylize, terminal, ExecutableCommand};

    for y in 0..40 {
        for x in 0..150 {
            if (y == 0 || y == 40 - 1) || (x == 0 || x == 150 - 1) {
                // in this loop we are more efficient by not flushing the buffer.
                stdout
                    .execute(crossterm::cursor::MoveTo(x, y))?
                    .execute(crossterm::style::PrintStyledContent("█".magenta()))?;
            }
        }
    }

    // _ = terminal::disable_raw_mode();
    // _ = stdout.execute(terminal::LeaveAlternateScreen);

    let (columns, rows) = crossterm::terminal::size().unwrap();
    let terminal_settings = TerminalSettings {
        width: columns as u64,
        height: rows as u64,
    };

    // let args_list = build_args_list(argc, argv, &roc_host);
    let result = unsafe { roc_init(RocList::<RocStr>::empty()) };
    // println!("init done");

    let init_effects = result.effects;
    let mut current_model = result.m;
    let mut current_subs = result.sub;

    handle_effects(init_effects.as_slice());

    loop {
        // view consumes the box (Box.unbox in Roc), so incref first to keep a
        // live reference for the subsequent roc_update call.
        unsafe { incref_box(current_model, 1) };
        let s = unsafe { roc_view(terminal_settings, current_model) };
        match s.tag {
            ViewForHostResultTag::Ok => {
                _ = stdout.execute(terminal::Clear(terminal::ClearType::All));
                _ = stdout.execute(crossterm::cursor::MoveTo(0, 0));
                let s = unsafe { s.payload.ok };
                for row in s.as_slice() {
                    _ = write!(stdout, "{}", row.as_str());
                    _ = stdout.execute(crossterm::cursor::MoveToNextLine(1));
                }
            }
            ViewForHostResultTag::Err => {}
        }

        let event = match wait_for_next_event(&current_subs, &roc_host) {
            Some(event) => event,
            None => return Ok(2),
        };

        let update_result = unsafe { roc_update(current_model, event) };
        handle_effects(update_result.effects.as_slice());
        current_model = update_result.m;
        current_subs = update_result.sub;
    }
}

fn wait_for_next_event(subs: &Subscriptions, roc_host: &RocHost) -> Option<*mut c_void> {
    let stdin_closure = match subs.stdin.tag {
        SubscriptionsStdinResultTag::Ok => unsafe { *subs.stdin.payload.ok },
        SubscriptionsStdinResultTag::Err => {
            return None;
        }
    };

    let Ok(stdin_listen_result) = stdin_listen(&roc_host) else {
        return None;
    };

    let event = unsafe { make_event_from_list_u8(stdin_closure, stdin_listen_result) };
    Some(event)
}

fn handle_effects(effects: &[Effect]) {
    for effect in effects {
        match effect.tag {
            EffectTag::Print => {
                let text = unsafe { *effect.payload.print };
                println!("Print: {}", text.as_str());
            }
            EffectTag::WriteToFile => {
                let filename = unsafe { effect.payload.write_to_file.filename };
                let content = unsafe { effect.payload.write_to_file.content };
                println!(
                    "WriteToFile: filename={} content={}",
                    filename.as_str(),
                    content.as_str()
                );
            }
        }
    }
}

fn stdin_listen(roc_host: &RocHost) -> Result<RocListWith<u8, false>, ()> {
    const BUF_SIZE: usize = 16_384;

    let stdin = std::io::stdin();

    // Get file descriptors for polling
    let stdin_fd = stdin.as_raw_fd();

    let mut fds = [libc::pollfd {
        fd: stdin_fd,
        events: libc::POLLIN,
        revents: 0,
    }];

    // Poll both file descriptors
    let result = unsafe { libc::poll(fds.as_mut_ptr(), 1, -1) };
    if result < 0 {
        return Err(());
    }

    // Check which fd is ready (prioritize stdin)
    if fds[0].revents & libc::POLLIN != 0 {
        let mut buffer: [u8; BUF_SIZE] = [0; BUF_SIZE];
        match stdin.lock().read(&mut buffer) {
            Ok(bytes_read) => {
                let raw = &buffer[0..bytes_read];
                let data = unsafe { RocListWith::<u8, false>::from_slice(raw, roc_host) };
                Ok(data)
            }
            Err(_io_err) => Err(()),
        }
    } else {
        Err(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    // Test something random
    #[test]
    fn test_something() {
        assert!(1 == 2);
    }
}
