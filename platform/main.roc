platform ""
	requires {
        [Model : model, Event : event] for application : {
                init : Context, List(Str) -> { m: model, sub: Subscriptions(event), effects: List(Effect) },
                update : Context, model, event -> { m: model, sub: Subscriptions(event), effects: List(Effect) },
                view : TerminalSettings, model -> [RawMode(List(List(Terminal))), Nothing]
            }
	}
	exposes []
	packages {
		ansi: "https://github.com/lukewilliamboswell/roc-ansi/releases/download/0.13.0/JXLM47L6CzrLXB5HBfqc27VnU6CD4jMm5Mk6dgbbovL.tar.zst",
		platform_pack: "../package/main.roc"
	}
	provides { # Rust calling Roc
        "roc_init": init_for_host,
        "roc_update": update_for_host,
        "roc_view": view_for_host,

        # Helpers for making events
        "make_event_from_str": make_event_from_str,
        "make_event_from_list_u8": make_event_from_list_u8,
        "make_event_from_tcp_connected": make_event_from_tcp_connected,
        "make_event_from_tcp_disconnected": make_event_from_tcp_disconnected,
        "make_event_from_tcp_receive": make_event_from_tcp_receive,
    }
	hosted { # Roc calling Rust
	}
	targets: {
		inputs_dir: "targets/",
		x64mac: { inputs: ["libhost.a", app] },
		arm64mac: { inputs: ["libhost.a", app] },
		x64win: { inputs: ["host.lib", "advapi32.lib", "bcrypt.lib", "crypt32.lib", "dbghelp.lib", "iphlpapi.lib", "kernel32.lib", "ncrypt.lib", "ntdll.lib", "ole32.lib", "secur32.lib", "shell32.lib", "user32.lib", "userenv.lib", "ws2_32.lib", app] },
		x64musl: { inputs: ["crt1.o", "libhost.a", "libunwind.a", app, "libc.a"] },
		arm64musl: { inputs: ["crt1.o", "libhost.a", "libunwind.a", app, "libc.a"] },
	}

import platform_pack.TerminalSettings
import platform_pack.Subscriptions
import platform_pack.Effect
import platform_pack.Terminal
import platform_pack.TcpStream
import platform_pack.Context
import ansi.ANSI

init_for_host : Context, List(Str) -> { m: Box(Model), sub: Subscriptions, effects: List(Effect) }
init_for_host = |ctx, args| {
    init_fn = application.init
    result = init_fn(ctx, args)
    boxed_model = Box.box(result.m)
    { m: boxed_model, sub: result.sub, effects: result.effects }
}

update_for_host : Context, Box(Model), Box(Event) -> { m: Box(Model), sub: Subscriptions, effects: List(Effect) }
update_for_host = |ctx, boxed_model, boxed_event| {
    model = Box.unbox(boxed_model)
    event = Box.unbox(boxed_event)
    update_fn = application.update
    res = update_fn(ctx, model, event)
    { m: Box.box(res.m), sub: res.sub, effects: res.effects }
}


view_for_host : TerminalSettings, Box(Model) -> Try(List(Str), [Nothing])
view_for_host = |settings, boxed_model| {
    model = Box.unbox(boxed_model)
    view_fn = application.view
    v = view_fn(settings, model)
    match (v) {
        RawMode(rows) => {
            Ok(rows->List.map(|row|
                row
                    ->List.map(|t| t.to_str())
                    ->Str.join_with("")
            ))
        }
        Nothing => Err(Nothing)
    }
}



make_event_from_str : Box(Str -> Event), Str -> Box(Event)
make_event_from_str = |boxed_fn, str| {
    fn = Box.unbox(boxed_fn)
    Box.box(fn(str))
}

make_event_from_list_u8 : Box(ANSI.Input -> Event), List(U8) -> Box(Event)
make_event_from_list_u8 = |boxed_fn, list_u8| {
    fn = Box.unbox(boxed_fn)
    input = ANSI.parse_raw_stdin(list_u8)
    Box.box(fn(input))
}

make_event_from_tcp_connected : Box(TcpStream -> Event), U64 -> Box(Event)
make_event_from_tcp_connected = |boxed_fn, stream_id| {
    fn = Box.unbox(boxed_fn)
    Box.box(fn(TcpStream.new(stream_id)))
}

make_event_from_tcp_disconnected : Box(TcpStream -> Event), U64 -> Box(Event)
make_event_from_tcp_disconnected = |boxed_fn, stream_id| {
    fn = Box.unbox(boxed_fn)
    Box.box(fn(TcpStream.new(stream_id)))
}

make_event_from_tcp_receive : Box((TcpStream, List(U8) -> Event)), U64, List(U8) -> Box(Event)
make_event_from_tcp_receive = |boxed_fn, stream_id, data| {
    fn = Box.unbox(boxed_fn)
    Box.box(fn(TcpStream.new(stream_id), data))
}
