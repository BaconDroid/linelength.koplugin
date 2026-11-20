-- Word count: shows how many words and characters you selected, inside the dialog that appears
-- after you select text (the one with Select, Highlight, Copy, Add note, Wikipedia, ...).
local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local util = require("util")
local _ = require("gettext")
local T = require("ffi/util").template

local Counter = require("wcount/counter")

local WordCount = WidgetContainer:extend{
    name = "wordcount",
    is_doc_only = true,
}

-- The highlight dialog lists its buttons sorted by this key. The built-in ones run from
-- 01_select to 12_search (the QR code plugin sits at 12_generate_qr_code), so "13" puts the count
-- last: on a row of its own when the number of other buttons is even.
local SLOT = "13_word_count"

-- Count what Copy would copy: the same clean-up KOReader applies before it puts the selection
-- on the clipboard (trims the ends, collapses runs of spaces, keeps single line breaks).
local function countSelection(highlight)
    local selected = highlight and highlight.selected_text
    local text = selected and selected.text
    if type(text) ~= "string" then
        text = ""
    end
    return Counter.count(util.cleanupSelectedText(text))
end

local function n(value)
    return string.format("%d", value)
end

function WordCount:init()
    -- Only in a book (self.document), and only if this KOReader has the highlight module.
    if not (self.document and self.ui and self.ui.highlight) then
        return
    end
    self.ui.highlight:addToHighlightDialog(SLOT, function(this)
        local c = countSelection(this)
        return {
            text = T(_("Words: %1 · Chars: %2"), n(c.words), n(c.chars)),
            callback = function()
                UIManager:show(InfoMessage:new{
                    text = T(_("Words: %1\nCharacters, with spaces: %2\nCharacters, without spaces: %3"),
                        n(c.words), n(c.chars), n(c.chars_no_spaces)),
                })
            end,
        }
    end)
end

return WordCount
