local _ = require("gettext")

return {
	fullname = _("Word count"),
	author = "Charliechin",
	description = _([[Adds one button to the dialog that appears when you select text. It shows how many
characters (spaces and symbols included) you selected and how that reads as a line of text:
Excellent, Comfortable, Still readable or Too long, in colour on colour screens. Tap it for the
character counts with and without spaces, the word count and the ranges.]]),
	version = "0.3.0",
}
