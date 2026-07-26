## Greet a name supplied as a native command-line argument.
app [ main!, Model, Event, application ] { pf: platform "../platform/main.roc" }

import pf.OsStr
import pf.Stdout
import pf.TerminalSettings
import pf.Subscriptions

application = {
    init : init,
    update : update,
    view : view,
}

Model : {
	name : Str
}

Event : [
    UserTyped(Str),
]

init : List(Str) -> { m: Model, sub: Subscriptions }
init = |_args| {
    m: { name: "Test WattApp" },
    sub: Subscriptions.{ stdin: Ok(Box.box(str_to_event)) },
}

update : Model, Event -> { m: Model, sub: Subscriptions }
update = |_model, event| {
    new_name = match (event) {
        UserTyped(what) => {
            what
        },
    }
    {
        m: { name: new_name },
        sub: Subscriptions.{ stdin: Ok(Box.box(str_to_event)) },
    }
}

str_to_event : Str -> Event
str_to_event = |what| UserTyped(what)

view : TerminalSettings, Model -> Str
view = |_settings, model| { model.name }


main! : List(OsStr) => Try({}, _)
main! = |args| {

	name : Str
	name = greeting_name(args)

	Stdout.line!("Hello, ${name}, from basic-cli!")?

	Ok({})
}

greeting_name : List(OsStr) -> Str
greeting_name = |args|
	match args.drop_first(1) {
		[first, ..] => OsStr.display(first)
		[] => "friend"
	}
