## Greet a name supplied as a native command-line argument.
app [Model, Event, application] { pf: platform "../platform/main.roc", ansi: "https://github.com/lukewilliamboswell/roc-ansi/releases/download/0.13.0/JXLM47L6CzrLXB5HBfqc27VnU6CD4jMm5Mk6dgbbovL.tar.zst", platform_pack: "../package/main.roc" }

import ansi.ANSI
import platform_pack.Context
import platform_pack.Terminal
import platform_pack.TerminalSettings
import platform_pack.Subscriptions
import platform_pack.Effect

application = {
	init: init,
	update: update,
	view: view,
}

Model : {
	name : Str,
	cursorPos : U16,
	timer : U64,
}

Event : [
	UserTyped(ANSI.Input),
]

init : Context, List(Str) -> { m : Model, sub : Subscriptions, effects : List(Effect) }
init = |ctx, _args| {
	m: { name: "Test WattApp", cursorPos: 0, timer: ctx.now_nanos + 1_000_000_000 },
	sub: Subscriptions.{
		stdin: Ok(Box.box(input_to_event)),
		accept_tcp_connection: Err(NotSubscribed),
		tcp_connect: Err(NotSubscribed),
		tcp_receive: Err(NotSubscribed),
		timer: Err(NotSubscribed),
	},
	effects: [],
}

update : Context, Model, Event -> { m : Model, sub : Subscriptions, effects : List(Effect) }
update = |_ctx, model, event| {
	(quit, new_model) = match (event) {
		UserTyped(Ctrl(C)) => (Bool.True, model)
		UserTyped(Arrow(Up)) => (Bool.False, { ..model, cursorPos: model.cursorPos - 1 })
		UserTyped(Arrow(Down)) => (Bool.False, { ..model, cursorPos: model.cursorPos + 1 })
		UserTyped(input) => (Bool.False, { ..model, name: ANSI.input_to_str(input), cursorPos: 2 })
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
				timer: Err(NotSubscribed),
			}
		},
		effects: [],
	}
}

input_to_event : ANSI.Input -> Event
input_to_event = |input| UserTyped(input)

view : TerminalSettings, Model -> [RawMode(List(List(Terminal))), Nothing]
view = |_settings, model| {
	selected = [Bg(Blue), Text("> ")]
	base = [Fg(Green), Text("  ")]
	RawMode(
		[
			[Text(model.name), Reset],
			[Text("Orange"), Reset],
			[Text("Banana"), Reset],
		].map_with_index(
			|item, index| {
				i = index |> U64.to_u16_wrap
				if (i == model.cursorPos) {
					List.concat(selected, item)
				} else {
					List.concat(base, item)
				}
			},
		),
	)
}
