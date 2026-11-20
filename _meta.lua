local _ = require("gettext")

return {
	fullname = _("Word count"),
	author = "Charliechin",
	description = _([[Checks how long the lines of a book are, in characters, and how that reads: Excellent,
Comfortable, Still readable or Too long. Select a line and tap the button in the highlight dialog, or
use "Line length: this page" in the Typeset menu to see the longest lines on the page. The card shows
the counts and the ranges, in colour on colour screens.]]),
	version = "0.6.0",
}
