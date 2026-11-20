import TcpStream
import TerminalSettings
import Subscriptions
import Effect
import Context
import Terminal

Application(event, model) := {
    init : Context, List(Str) -> { m : model, sub : Subscriptions(event), effects : List(Effect) },
    update : Context, model, event -> { m : model, sub : Subscriptions(event), effects : List(Effect) },
    view : TerminalSettings, model -> [RawMode(List(List(Terminal))), Nothing]
}
