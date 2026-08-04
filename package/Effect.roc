import TcpStream

Effect := [
	Print(Str),
	WriteToFile({ filename: Str, content: Str }),
	TcpSend({ stream: TcpStream, data: List(U8) }),
	Exit(U16),
]
