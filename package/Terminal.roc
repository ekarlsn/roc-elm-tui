Terminal := [
	Fg(Color),
	Bg(Color),
	Bold,
	Dim,
	Italic,
	Underline,
	Strikethrough,
	Text(Str),
	Reset,
].{
	to_str : Terminal -> Str
	to_str = |t| {
		esc = "\u(001b)["
		match t {
			Fg(color) => "${esc}${color_fg_code(color)}m"
			Bg(color) => "${esc}${color_bg_code(color)}m"
			Bold => "${esc}1m"
			Dim => "${esc}2m"
			Italic => "${esc}3m"
			Underline => "${esc}4m"
			Strikethrough => "${esc}9m"
			Text(str) => str
			Reset => "${esc}0m"
		}
	}
}

Color : [
	Black,
	Red,
	Green,
	Yellow,
	Blue,
	Magenta,
	Cyan,
	White,
	BrightBlack,
	BrightRed,
	BrightGreen,
	BrightYellow,
	BrightBlue,
	BrightMagenta,
	BrightCyan,
	BrightWhite,
]

color_fg_code : Color -> Str
color_fg_code = |color| match color {
	Black => "30"
	Red => "31"
	Green => "32"
	Yellow => "33"
	Blue => "34"
	Magenta => "35"
	Cyan => "36"
	White => "37"
	BrightBlack => "90"
	BrightRed => "91"
	BrightGreen => "92"
	BrightYellow => "93"
	BrightBlue => "94"
	BrightMagenta => "95"
	BrightCyan => "96"
	BrightWhite => "97"
}

color_bg_code : Color -> Str
color_bg_code = |color| match color {
	Black => "40"
	Red => "41"
	Green => "42"
	Yellow => "43"
	Blue => "44"
	Magenta => "45"
	Cyan => "46"
	White => "47"
	BrightBlack => "100"
	BrightRed => "101"
	BrightGreen => "102"
	BrightYellow => "103"
	BrightBlue => "104"
	BrightMagenta => "105"
	BrightCyan => "106"
	BrightWhite => "107"
}
