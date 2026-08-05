TcpStream :: { id : U64 }.{
	new : U64 -> TcpStream
	new = |id| { id: id }

	is_eq : TcpStream, TcpStream -> Bool
	is_eq = |a, b| a.id == b.id
}
