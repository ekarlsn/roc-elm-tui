## TCP client example — connects to a remote server and sends/receives messages.
app [ Model, Event, application ] {
    pf: platform "../platform/main.roc",
    ansi: "https://github.com/lukewilliamboswell/roc-ansi/releases/download/0.13.0/JXLM47L6CzrLXB5HBfqc27VnU6CD4jMm5Mk6dgbbovL.tar.zst",
    platform_pack: "../package/main.roc"
}

import platform_pack.TerminalSettings
import platform_pack.Subscriptions
import platform_pack.Effect
import platform_pack.Terminal
import platform_pack.TcpStream
import platform_pack.Context
import ansi.ANSI

application = {
    init: init,
    update: update,
    view: view,
}

Model : {
    connection: [NotConnected, Connected(TcpStream), Disconnected],
    messages: List(Str),
    message_count: U64,
}

Event : [
    ServerConnected(TcpStream),
    ServerDisconnected(TcpStream),
    MessageReceived(TcpStream, List(U8)),
    UserInput(ANSI.Input),
]

# Configuration for the server to connect to
server_address : Str
server_address = "127.0.0.1"

server_port : U16
server_port = 8080.U16

init : Context, List(Str) -> { m: Model, sub: Subscriptions(Event), effects: List(Effect) }
init = |_ctx, _args| {
    m = {
        connection: NotConnected,
        messages: [],
        message_count: 0,
    }
    sub = Subscriptions.{
        stdin: Ok(Box.box(|input| UserInput(input))),
        accept_tcp_connection: Err(NotSubscribed),
        tcp_connect: Ok({
            address: server_address,
            port: server_port,
            on_connected: Box.box(|stream| ServerConnected(stream)),
            on_disconnected: Box.box(|stream| ServerDisconnected(stream)),
        }),
        tcp_receive: Ok(Box.box(|stream, data| MessageReceived(stream, data))),
        timer: Err(NotSubscribed),
    }
    { m, sub, effects: [] }
}

update : Context, Model, Event -> { m: Model, sub: Subscriptions(Event), effects: List(Effect) }
update = |_ctx, model, event| {
    match event {
        ServerConnected(stream) => {
            new_model = { ..model,
                connection: Connected(stream),
                messages: model.messages.append("✓ Connected to server"),
            }
            { m: new_model, sub: get_subs(new_model), effects: [] }
        }

        ServerDisconnected(_) => {
            new_model = { ..model,
                connection: Disconnected,
                messages: model.messages.append("✗ Disconnected from server"),
            }
            { m: new_model, sub: get_subs(new_model), effects: [] }
        }

        MessageReceived(_, data) => {
            message_str = data->List.map(|byte| byte.to_str())->Str.join_with(" ")
            new_model = { ..model,
                messages: model.messages.append("← Received: ${message_str}"),
            }
            { m: new_model, sub: get_subs(new_model), effects: [] }
        }

        UserInput(Ctrl(C)) => {
            { m: model, sub: Subscriptions.none, effects: [Exit(0)] }
        }
        UserInput(input) => {
            # Send a message when any key is pressed (except Ctrl+C)
            match model.connection {
                Connected(stream) => {
                    new_count = model.message_count + 1
                    message = "Hello ${new_count.to_str()}: ${ANSI.input_to_str(input)}"
                    data = Str.to_utf8(message)
                    effects = [TcpSend({ stream, data })]
                    new_model = { ..model,
                        message_count: new_count,
                        messages: model.messages.append("→ Sent: ${message}"),
                    }
                    { m: new_model, sub: get_subs(new_model), effects }
                }
                _ => {
                    new_model = { ..model,
                        messages: model.messages.append("✗ Not connected"),
                    }
                    { m: new_model, sub: get_subs(new_model), effects: [] }
                }
            }
        }
    }
}

get_subs : Model -> Subscriptions(Event)
get_subs = |_model| {
    Subscriptions.{
        stdin: Ok(Box.box(|input| UserInput(input))),
        accept_tcp_connection: Err(NotSubscribed),
        tcp_connect: Ok({
            address: server_address,
            port: server_port,
            on_connected: Box.box(|stream| ServerConnected(stream)),
            on_disconnected: Box.box(|stream| ServerDisconnected(stream)),
        }),
        tcp_receive: Ok(Box.box(|stream, data| MessageReceived(stream, data))),
        timer: Err(NotSubscribed),
    }
}

view : TerminalSettings, Model -> [RawMode(List(List(Terminal))), Nothing]
view = |_settings, model| {
    connection_status = match model.connection {
        NotConnected => [Fg(Yellow), Text("⏳ Connecting..."), Reset]
        Connected(_) => [Fg(Green), Text("✓ Connected"), Reset]
        Disconnected => [Fg(Red), Text("✗ Disconnected"), Reset]
    }

    message_rows = model.messages
        ->List.take_last(10)
        ->List.map(|msg| [Fg(BrightBlack), Text(msg), Reset])

    header = [
        [Bold, Fg(Cyan), Text("TCP Client"), Reset],
        [Text("Server: ${server_address}:${server_port.to_str()}")],
        connection_status,
        [],
        [Dim, Text("Messages (last 10):"), Reset],
    ]

    footer = [
        [],
        [Dim, Text("Press any key to send a message, Ctrl+C to exit"), Reset],
    ]

    rows = List.concat(header, message_rows)
    rows_with_footer = List.concat(rows, footer)

    RawMode(rows_with_footer)
}
