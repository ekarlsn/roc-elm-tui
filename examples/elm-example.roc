## Greet a name supplied as a native command-line argument.
app [ main!, Model, application ] { pf: platform "../platform/main.roc" }

import pf.OsStr
import pf.Stdout
import pf.Event
import pf.TerminalSettings
import pf.Subscriptions

Model : {
	name : Str
}

application = {
    init : init,
    update : update,
    view : view,
}

init : List(Str) -> Model
init = |_args| { name: "Test WattApp" }

update : Model, Event -> { m: Model }
update = |_model, _event| {
    { m: { name: "Updated" } }
}

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
