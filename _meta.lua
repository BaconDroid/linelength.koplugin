local _ = require("gettext")

return {
	fullname = _("Word count"),
	author = "Charliechin",
	description = _([[Adds one button to the dialog that appears when you select text. It shows how many
characters (spaces and symbols included) you selected and how that reads as a line of text:
Excellent, Comfortable, Still readable or Too long. Tap it for a card with the character counts
with and without spaces, the word count and the ranges, in colour on colour screens.]]),
	version = "0.5.0",
}
