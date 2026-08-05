## TCP echo server — every message received from any client is
## broadcast back to ALL currently connected clients.
app [Model, Event, application] { pf: platform "../platform/main.roc", platform_pack: "../package/main.roc" }

import platform_pack.TerminalSettings
import platform_pack.Subscriptions
import platform_pack.Effect
import platform_pack.Terminal
import platform_pack.TcpStream
import platform_pack.Context

application = {
	init: init,
	update: update,
	view: view,
}

Model : {
	clients : List(TcpStream),
	log : List(Str),
}

Event : [
	ClientConnected(TcpStream),
	ClientDisconnected(TcpStream),
	MessageReceived(TcpStream, List(U8)),
]

listen_host : Str
listen_host = "0.0.0.0"

listen_port : U16
listen_port = 8080.U16

# Subscriptions are constant — the Rust host manages the active connection
# set internally, so we always subscribe to both accept and receive.
subs : Subscriptions(Event)
subs = Subscriptions.{
	stdin: Err(NotSubscribed),
	accept_tcp_connection: Ok({
		host: listen_host,
		port: listen_port,
		on_connected: Box.box(|stream| ClientConnected(stream)),
		on_disconnected: Box.box(|stream| ClientDisconnected(stream)),
	}),
	tcp_connect: Err(NotSubscribed),
	tcp_receive: Ok(Box.box(|stream, data| MessageReceived(stream, data))),
	timer: Err(NotSubscribed),
}

init : Context, List(Str) -> { m : Model, sub : Subscriptions(Event), effects : List(Effect) }
init = |_ctx, _args| {
	m: { clients: [], log: [] },
	sub: subs,
	effects: [],
}

update : Context, Model, Event -> { m : Model, sub : Subscriptions(Event), effects : List(Effect) }
update = |_ctx, model, event| {
	match event {
		ClientConnected(stream) => {
			new_model = {
				..model,
				clients: model.clients.append(stream),
				log: model.log.append("+ client connected"),
			}
			{ m: new_model, sub: subs, effects: [] }
		}

		ClientDisconnected(stream) => {
			new_model = {
				..model,
				clients: model.clients.keep_if(|s| s != stream),
				log: model.log.append("- client disconnected"),
			}
			{ m: new_model, sub: subs, effects: [] }
		}

		MessageReceived(_, data) => {
			# Broadcast the raw bytes back to every connected client.
			effects = model.clients.map(|client| TcpSend({ stream: client, data }))
			entry = "~ echoed ${data.len().to_str()} bytes → ${model.clients.len().to_str()} client(s)"
			new_model = { ..model, log: model.log.append(entry) }
			{ m: new_model, sub: subs, effects }
		}
	}
}

view : TerminalSettings, Model -> [RawMode(List(List(Terminal))), Nothing]
view = |_settings, model| {
	log_rows = model.log.map(|entry| [Fg(BrightBlack), Text(entry), Reset])

	header = [
		[Bold, Fg(Cyan), Text("TCP Echo Server"), Reset],
		[Text("Listening on ${listen_host}:${listen_port.to_str()}")],
		[Fg(Green), Text("Connected clients: ${model.clients.len().to_str()}"), Reset],
		[],
		[Dim, Text("Activity log:"), Reset],
	]

	RawMode(List.concat(header, log_rows))
}
