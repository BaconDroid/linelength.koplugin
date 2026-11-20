-- Word count: shows how many words and characters you selected, and how that line length reads,
-- inside the dialog that appears after you select text (Select, Highlight, Copy, Add note, ...).
local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local logger = require("logger")
local util = require("util")
local _ = require("gettext")
local T = require("ffi/util").template

local Counter = require("wcount/counter")
local Rating = require("wcount/rating")

local WordCount = WidgetContainer:extend{
    name = "wordcount",
    is_doc_only = true,
}

-- The highlight dialog lists its buttons sorted by these keys. The built-in ones run from
-- 01_select to 12_search (the QR code plugin sits at 12_generate_qr_code), so "13" and "14" put the
-- count and the rating last: side by side on a row of their own when the number of other buttons
-- is even.
local COUNT_SLOT = "13_word_count"
local RATING_SLOT = "14_line_length"
local RATING_ID = "wordcount_rating"

local LABELS = {
    too_long = _("Too long"),
    still_readable = _("Still readable"),
    comfortable = _("Comfortable"),
    excellent = _("Excellent"),
    short = _("Short"),
}

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

-- "45–54  Excellent" lines for the popup, lowest band first, built from the same table as the rating.
local function legend()
    local tiers = Rating.TIERS
    local lines = {}
    for i = #tiers - 1, 1, -1 do
        local tier = tiers[i]
        local upper = tiers[i - 1] and (tiers[i - 1].min - 1)
        local range = upper and string.format("%d–%d", tier.min, upper) or string.format("%d+", tier.min)
        lines[#lines + 1] = range .. "  " .. LABELS[tier.id]
    end
    return table.concat(lines, "\n")
end

local function showBreakdown(c)
    UIManager:show(InfoMessage:new{
        text = T(_("Words: %1\nCharacters, with spaces: %2\nCharacters, without spaces: %3"),
                n(c.words), n(c.chars), n(c.chars_no_spaces))
            .. "\n\n" .. _("Characters per line (select one line):") .. "\n" .. legend(),
    })
end

-- Colour only when KOReader is actually drawing in colour: that is true on a colour screen unless
-- the user turned "Color rendering" off. On a black-and-white screen, or with colour off, the text
-- keeps its standard colour.
local function colorEnabled()
    local ok, enabled = pcall(function() return Device.screen:isColorEnabled() end)
    return ok and enabled == true
end

-- A dialog button has no text-colour option (ButtonTable forwards a fixed list of fields), so once
-- the dialog exists we reach the button through ButtonDialog.buttontable.button_by_id and set the
-- colour of its label, which TextWidget reads when it paints. Anything unexpected leaves the text
-- in the standard colour.
local function tint(highlight, tier)
    local r, g, b = Rating.parseHex(tier.color)
    local dialog = highlight and highlight.highlight_dialog
    local button_table = dialog and dialog.buttontable
    local button = button_table and button_table.button_by_id and button_table.button_by_id[RATING_ID]
    local label = button and button.label_widget
    if not (r and label) then
        logger.dbg("wordcount: could not colour the rating button")
        return
    end
    label.fgcolor = Blitbuffer.ColorRGB32(r, g, b, 0xFF)
    if label.update then -- a TextBoxWidget needs a redraw to take the new colour
        label:update()
    end
    -- Normally this runs before the dialog's first paint. If it already painted, redraw the button.
    local dimen = button.dimen
    if dimen and dimen.x and dimen.y then
        UIManager:setDirty(dialog, "ui", dimen)
    end
end

function WordCount:init()
    -- Only in a book (self.document), and only if this KOReader has the highlight module.
    if not (self.document and self.ui and self.ui.highlight) then
        return
    end

    self.ui.highlight:addToHighlightDialog(COUNT_SLOT, function(this)
        local c = countSelection(this)
        return {
            text = T(_("Words: %1 · Chars: %2"), n(c.words), n(c.chars)),
            callback = function() showBreakdown(c) end,
        }
    end)

    self.ui.highlight:addToHighlightDialog(RATING_SLOT, function(this)
        local c = countSelection(this)
        local tier = Rating.forChars(c.chars)
        if tier.color and colorEnabled() then
            -- Runs after the dialog has been built from the buttons returned here.
            UIManager:nextTick(function()
                local ok, err = pcall(tint, this, tier)
                if not ok then
                    logger.warn("wordcount: colouring failed:", err)
                end
            end)
        end
        return {
            id = RATING_ID,
            text = LABELS[tier.id],
            callback = function() showBreakdown(c) end,
        }
    end)
end

return WordCount
