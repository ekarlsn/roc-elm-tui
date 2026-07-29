## A native command-line platform with filesystem, process, network, terminal,
## SQLite, environment, random, and UTC effects.
platform ""
	requires {
        [Model : model, Event : event] for application : {
                init : List(Str) -> { m: model, sub: Subscriptions(event), effects: List(Effect) },
                update : model, event -> { m: model, sub: Subscriptions(event), effects: List(Effect) },
                view : TerminalSettings, model -> List(List(Terminal))
            }
	}
	exposes [Effect, Subscriptions, TerminalSettings, Terminal]
	packages {
		# HTTP data types (Method, Request, Response) come from the shared
		# roc-lang/http package so apps and other packages using it see the same
		# nominal types. The platform supplies only the effectful `Http.send!`.
		http: "https://github.com/roc-lang/http/releases/download/1.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
		# ANSI input parsing (parse_raw_stdin) and escape sequences.
		# Apps that handle stdin events must also declare this package at the same URL
		# so that ANSI.Input resolves to the same nominal type on both sides.
		ansi: "https://github.com/lukewilliamboswell/roc-ansi/releases/download/0.13.0/JXLM47L6CzrLXB5HBfqc27VnU6CD4jMm5Mk6dgbbovL.tar.zst",
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
import Terminal
import ansi.ANSI

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


view_for_host : TerminalSettings, Box(Model) -> List(Str)
view_for_host = |settings, boxed_model| {
    model = Box.unbox(boxed_model)
    view_fn = application.view
    rows = view_fn(settings, model)
    rows->List.map(|row|
        row
            ->List.map(terminal_to_str)
            ->Str.join_with("")
    )
}

color_fg_code = |color| match color {
    Black => "30"
    Red => "31"
    Green => "32"
    Yellow => "33"
    Blue => "34"
    Magenta => "35"
    Cyan => "36"
    White => "37"
    BrightBlack => "90"
    BrightRed => "91"
    BrightGreen => "92"
    BrightYellow => "93"
    BrightBlue => "94"
    BrightMagenta => "95"
    BrightCyan => "96"
    BrightWhite => "97"
}

color_bg_code = |color| match color {
    Black => "40"
    Red => "41"
    Green => "42"
    Yellow => "43"
    Blue => "44"
    Magenta => "45"
    Cyan => "46"
    White => "47"
    BrightBlack => "100"
    BrightRed => "101"
    BrightGreen => "102"
    BrightYellow => "103"
    BrightBlue => "104"
    BrightMagenta => "105"
    BrightCyan => "106"
    BrightWhite => "107"
}

terminal_to_str : Terminal -> Str
terminal_to_str = |t| {
    esc = "\u(001b)["
    match (t) {
        Fg(color) => "${esc}${color_fg_code(color)}m"
        Bg(color) => "${esc}${color_bg_code(color)}m"
        Bold => "${esc}1m"
        Dim => "${esc}2m"
        Italic => "${esc}3m"
        Underline => "${esc}4m"
        Strikethrough => "${esc}9m"
        Text(str) => str
        Reset => "${esc}0m"
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
