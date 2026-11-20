-- Word count: after you select text, adds one button to the dialog (Select, Highlight, Copy, ...)
-- that shows the length of the selection in characters and how that reads as a line of text.
-- Tap it for the details: characters with and without spaces, words, and the ranges.
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

-- The highlight dialog lists its buttons sorted by this key. The built-in ones run from
-- 01_select to 12_search (the QR code plugin sits at 12_generate_qr_code), so "13" puts ours last:
-- alone on a full-width row when the number of other buttons is even.
local SLOT = "13_line_length"
local BUTTON_ID = "wordcount_line_length"

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

local function showDetails(c)
    UIManager:show(InfoMessage:new{
        text = T(_("Characters, with spaces: %1\nCharacters, without spaces: %2\nWords: %3"),
                n(c.chars), n(c.chars_no_spaces), n(c.words))
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
-- colour of its label, which TextWidget reads when it paints.
--
-- Setting the colour is not enough on a colour e-ink screen: the dialog is drawn with a "ui"
-- refresh, and on Kaleido screens that waveform never shows colour (the framebuffer driver only
-- switches to a colour waveform for "partial" or "full" refreshes that carry the dither flag).
-- So the button is also redrawn with a dithered "partial" refresh, which uses the colour REAGL waveform.
local function tint(highlight, tier)
    local r, g, b = Rating.parseHex(tier.color)
    local dialog = highlight and highlight.highlight_dialog
    local button_table = dialog and dialog.buttontable
    local button = button_table and button_table.button_by_id and button_table.button_by_id[BUTTON_ID]
    local label = button and button.label_widget
    if not (r and label) then
        logger.warn("wordcount: could not colour the button: dialog or button not found")
        return
    end
    label.fgcolor = Blitbuffer.ColorRGB32(r, g, b, 0xFF)
    if label.update then -- a TextBoxWidget needs a redraw to take the new colour
        label:update()
    end
    local region = button.dimen
    if not (region and region.x and region.y) then
        region = dialog.dimen
    end
    local refreshed = region and region.x and region.y
    if refreshed then
        UIManager:setDirty(dialog, "partial", region, true)
    end
    logger.info("wordcount: coloured the line length button", tier.id, tier.color,
        refreshed and "refreshed" or "no region to refresh")
end

function WordCount:init()
    -- Only in a book (self.document), and only if this KOReader has the highlight module.
    if not (self.document and self.ui and self.ui.highlight) then
        return
    end

    self.ui.highlight:addToHighlightDialog(SLOT, function(this)
        local c = countSelection(this)
        local tier = Rating.forChars(c.chars)
        if tier.color and colorEnabled() then
            -- Two ticks from now: the dialog has been built from the button returned below and
            -- painted once, so the button exists and has a position on screen.
            UIManager:tickAfterNext(function()
                local ok, err = pcall(tint, this, tier)
                if not ok then
                    logger.warn("wordcount: colouring failed:", err)
                end
            end)
        end
        return {
            id = BUTTON_ID,
            text = T(_("Line: %1 chars · %2"), n(c.chars), LABELS[tier.id]),
            callback = function() showDetails(c) end,
        }
    end)
end

return WordCount
