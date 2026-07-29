## A native command-line platform with filesystem, process, network, terminal,
## SQLite, environment, random, and UTC effects.
platform ""
	requires {
        [Model : model, Event : event] for application : {
                init : List(Str) -> { m: model, sub: Subscriptions(event), effects: List(Effect) },
                update : model, event -> { m: model, sub: Subscriptions(event), effects: List(Effect) },
                view : TerminalSettings, model -> Str
            }
	}
	exposes [Effect, Subscriptions, TerminalSettings]
	packages {
		# HTTP data types (Method, Request, Response) come from the shared
		# roc-lang/http package so apps and other packages using it see the same
		# nominal types. The platform supplies only the effectful `Http.send!`.
		http: "https://github.com/roc-lang/http/releases/download/1.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
	}
	provides { # Rust calling Roc
        "roc_init": init_for_host,
        "roc_update": update_for_host,
        "roc_view": view_for_host,

        # Helpers for making events
        "make_event_from_str": make_event_from_str,
        "make_event_from_list_u8": make_event_from_list_u8,
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

import TerminalSettings
import Subscriptions
import Effect

init_for_host : List(Str) -> { m: Box(Model), sub: Subscriptions, effects: List(Effect) }
init_for_host = |args| {
    init_fn = application.init
    result = init_fn(args)
    boxed_model = Box.box(result.m)
    { m: boxed_model, sub: result.sub, effects: result.effects }
}

update_for_host : Box(Model), Box(Event) -> { m: Box(Model), sub: Subscriptions, effects: List(Effect) }
update_for_host = |boxed_model, boxed_event| {
    model = Box.unbox(boxed_model)
    event = Box.unbox(boxed_event)
    update_fn = application.update
    res = update_fn(model, event)
    { m: Box.box(res.m), sub: res.sub, effects: res.effects }
}


view_for_host : TerminalSettings, Box(Model) -> Str
view_for_host = |settings, boxed_model| {
    model = Box.unbox(boxed_model)
    view_fn = application.view
    view_fn(settings, model)
}

make_event_from_str : Box(Str -> Event), Str -> Box(Event)
make_event_from_str = |boxed_fn, str| {
    fn = Box.unbox(boxed_fn)
    Box.box(fn(str))
}

make_event_from_list_u8 : Box(List(U8) -> Event), List(U8) -> Box(Event)
make_event_from_list_u8 = |boxed_fn, list_u8| {
    fn = Box.unbox(boxed_fn)
    Box.box(fn(list_u8))
}
