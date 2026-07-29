## Greet a name supplied as a native command-line argument.
app [ Model, Event, application ] { pf: platform "../platform/main.roc" }

import pf.TerminalSettings
import pf.Subscriptions
import pf.Effect

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

init : List(Str) -> { m: Model, sub: Subscriptions, effects: List(Effect) }
init = |_args| {
    m: { name: "Test WattApp" },
    sub: Subscriptions.{ stdin: Ok(Box.box(str_to_event)) },
    effects: [Print("Katten musen"), Print("Tio Tusen")],
}

update : Model, Event -> { m: Model, sub: Subscriptions, effects: List(Effect) }
update = |_model, event| {
    new_name = match (event) {
        UserTyped(what) => {
            what
        },
    }
    {
        m: { name: new_name },
        sub: Subscriptions.{ stdin: Ok(Box.box(str_to_event)) },
        effects: [Print("Hello from Roc")],
    }
}

str_to_event : List(U8) -> Event
str_to_event = |what| UserTyped(Str.from_utf8_lossy(what))

view : TerminalSettings, Model -> Str
view = |_settings, model| { model.name }
