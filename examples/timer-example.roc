## Timer example - fires every 5 seconds
##
## NOTE: This example triggers a compiler crash in Roc nightly-2026-August-04-1cb06bc
## when using the timer subscription. The platform implementation is correct,
## but the compiler has a bug with `Box(U64 -> event)` types in subscriptions.
##
## Once the compiler bug is fixed, this example should compile and run successfully.

app [ Model, Event, application ] {
    pf: platform "../platform/main.roc",
    ansi: "https://github.com/lukewilliamboswell/roc-ansi/releases/download/0.13.0/JXLM47L6CzrLXB5HBfqc27VnU6CD4jMm5Mk6dgbbovL.tar.zst",
	platform_pack: "../package/main.roc"
}

import ansi.ANSI
import platform_pack.Context
import platform_pack.Terminal
import platform_pack.TerminalSettings
import platform_pack.Subscriptions
import platform_pack.Effect

application = {
    init : init,
    update : update,
    view : view,
}

Model : { count : U64 }

Event : [
    UserTyped(ANSI.Input),
    TimerFired,
]

input_to_event : ANSI.Input -> Event
input_to_event = |input| UserTyped(input)

timer_to_event : U64 -> Event
timer_to_event = |_| TimerFired

init : Context, List(Str) -> { m: Model, sub: Subscriptions, effects: List(Effect) }
init = |ctx, _args| {
    # Set timer to fire 5 seconds from now (5 billion nanoseconds)
    fireAt = ctx.now_nanos + 5_000_000_000

    {
        m: { count: 0 },
        sub: Subscriptions.{
            stdin: Ok(Box.box(input_to_event)),
            accept_tcp_connection: Err(NotSubscribed),
            tcp_connect: Err(NotSubscribed),
            tcp_receive: Err(NotSubscribed),
            # The timer subscription: fires when ctx.now_nanos >= fire_at
            # The callback receives a dummy U64 parameter (always 0)
            timer: Ok({ fire_at: fireAt, on_fire: Box.box(timer_to_event) }),
        },
        effects: [],
    }
}

update : Context, Model, Event -> { m: Model, sub: Subscriptions, effects: List(Effect) }
update = |ctx, model, event| {
    (quit, new_model, fire_at) = match (event) {
        UserTyped(Ctrl(C)) => (Bool.True, { count: 0 }, 0),
        UserTyped(_) => (Bool.False, model, ctx.now_nanos + 5_000_000_000),
        TimerFired => {
            # Timer fired! Increment count and set next timer
            (Bool.False, { count: model.count + 1 }, ctx.now_nanos + 5_000_000_000)
        }
    }
    {
        m: new_model,
        sub: if (quit) {
            Subscriptions.none
        } else {
            Subscriptions.{
                stdin: Ok(Box.box(input_to_event)),
                accept_tcp_connection: Err(NotSubscribed),
                tcp_connect: Err(NotSubscribed),
                tcp_receive: Err(NotSubscribed),
                # Re-subscribe to the timer for it to fire again
                timer: Ok({ fire_at: fire_at, on_fire: Box.box(timer_to_event) }),
            }
        },
        effects: [],
    }
}

view : TerminalSettings, Model -> [RawMode(List(List(Terminal))), Nothing]
view = |_settings, model| {
    count_str = U64.to_str(model.count)

    RawMode([
        [Fg(Green), Text("═══ Timer Example ═══"), Reset],
        [Text(""), Reset],
        [Text("Timer has fired: "), Fg(Yellow), Text(count_str), Fg(White), Text(" times"), Reset],
        [Text(""), Reset],
        [Fg(Cyan), Text("Press Ctrl+C to exit"), Reset],
        [Text(""), Reset],
        [Fg(Gray), Text("Timer fires every 5 seconds"), Reset],
    ])
}
