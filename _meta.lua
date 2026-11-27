local _ = require("gettext")

return {
	fullname = _("Line length"),
	author = "Charliechin",
	description = _([[Checks how long the lines of a book are, in characters, and how that reads: Excellent,
Comfortable, Still readable or Too long. Select a line and tap the button in the highlight dialog, or
use "Line length: this page" in the Typeset menu to see the longest lines on the page. The card shows
the counts and the ranges, in colour on colour screens. The page card has steppers for the margins and
the text size, which measure the page again after each tap, and Cancel, Accept and Done buttons.
--
-- It can also measure a sample of the book, and tune the margins of a book when it is opened at
-- its first page, so that the lines hold a good length.]]),
	version = "0.9.0",
}
