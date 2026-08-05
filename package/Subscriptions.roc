import ansi.ANSI
import TcpStream

Subscriptions(event) := {
	stdin : Try(Box(ANSI.Input -> event), [NotSubscribed]),
	accept_tcp_connection : Try(
		{
			host : Str,
			port : U16,
			on_connected : Box(TcpStream -> event),
			on_disconnected : Box(TcpStream -> event),
		},
		[NotSubscribed],
	),
	tcp_connect : Try(
		{
			address : Str,
			port : U16,
			on_connected : Box(TcpStream -> event),
			on_disconnected : Box(TcpStream -> event),
		},
		[NotSubscribed],
	),
	tcp_receive : Try(Box((TcpStream, List(U8) -> event)), [NotSubscribed]),
	timer : Try({ fire_at : U64, on_fire : Box(event) }, [NotSubscribed]),
}.{
	none : Subscriptions(a)
	none = {
		stdin: Err(NotSubscribed),
		accept_tcp_connection: Err(NotSubscribed),
		tcp_connect: Err(NotSubscribed),
		tcp_receive: Err(NotSubscribed),
		timer: Err(NotSubscribed),
	}
}
