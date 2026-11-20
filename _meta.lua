local _ = require("gettext")

return {
	fullname = _("Word count"),
	author = "Charliechin",
	description = _([[Adds the number of words and characters (spaces included) of the selected text
to the dialog that appears when you select text, plus a line-length rating (Excellent, Comfortable,
Still readable, Too long) for the characters in one selected line. The rating is coloured when the
screen shows colour. Tap either button for the full breakdown.]]),
	version = "0.2.0",
}
