-- Line length. Two ways in:
--  * select text: adds one button to the dialog (Select, Highlight, Copy, ...) that shows the length of
--    the selection in characters and how that reads as a line of text. Tap it for the details: characters
--    with and without spaces, words, and the ranges.
--  * the whole page: "Line length: this page" in the Typeset menu (also an action you can put on a gesture)
--    shows the longest lines on the page that is on screen, rated by the longest one.
local Device = require("device")
local Dispatcher = require("dispatcher")
local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local logger = require("logger")
local util = require("util")
local _ = require("gettext")
local T = require("ffi/util").template

local Counter = require("linelength/counter")
local PageLines = require("linelength/pagelines")
local Rating = require("linelength/rating")
local Report = require("linelength/report")

local LineLength = WidgetContainer:extend{
    name = "linelength",
    is_doc_only = true,
}

-- The highlight dialog lists its buttons sorted by this key. The built-in ones run from
-- 01_select to 12_search (the QR code plugin sits at 12_generate_qr_code), so "13" puts ours last:
-- alone on a full-width row when the number of other buttons is even.
local SLOT = "13_line_length"

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

-- Colour only when KOReader is actually drawing in colour: that is true on a colour screen unless
-- the user turned "Color rendering" off. On a black-and-white screen, or with colour off, the card
-- uses the standard text colour.
local function colorEnabled()
    local ok, enabled = pcall(function() return Device.screen:isColorEnabled() end)
    return ok and enabled == true
end

-- The same information as the card, as plain text. Used if the card cannot be built.
local function plainText(report)
    local lines = {}
    for _i, band in ipairs(report.bands) do
        lines[#lines + 1] = band.range .. "  " .. band.label
    end
    if report.lines then
        local rows = {}
        for _i, line in ipairs(report.lines) do
            rows[#rows + 1] = (line.number and ("L" .. n(line.number) .. ": ") or "") .. line.snippet .. "  " .. n(line.chars)
        end
        return _("Longest lines on this page (characters):") .. "\n" .. table.concat(rows, "\n")
            .. "\n\n" .. table.concat(lines, "\n")
    end
    return T(_("Characters, with spaces: %1\nCharacters, without spaces: %2\nWords: %3"),
            n(report.chars), n(report.chars_no_spaces), n(report.words))
        .. "\n\n" .. _("Characters per line (select one line):") .. "\n" .. table.concat(lines, "\n")
end

local function showReport(report)
    -- The card is loaded on demand and guarded: whatever goes wrong with it, the button stays and
    -- the information is still shown.
    local ok, err = pcall(function()
        local Details = require("linelength/details")
        UIManager:show(Details:new{ report = report, use_color = colorEnabled() })
    end)
    if not ok then
        logger.warn("linelength: could not show the details card, using plain text:", err)
        UIManager:show(InfoMessage:new{ text = plainText(report) })
    end
end

local function showDetails(counts)
    showReport(Report.build(counts, LABELS))
end

-- How many of the longest lines of a page are listed.
local TOP_LINES = 3

-- The report for the page on screen: nil and a reason when there is nothing to measure.
local function pageReport(ui)
    local doc = ui and ui.document
    -- Only books that reflow (EPUB and the like) have lines of text to read; a PDF or a comic does not.
    if not (ui and ui.rolling and doc and doc.getTextFromPositions and doc.getScreenPositionFromXPointer
            and doc.getTextFromXPointers) then
        return nil, "unsupported"
    end
    local screen = Device.screen
    local lines = PageLines.collect(doc, screen:getWidth(), screen:getHeight(), util.cleanupSelectedText)
    local top = PageLines.longest(lines, TOP_LINES)
    if #top == 0 then
        return nil, "empty"
    end
    return Report.buildPage(top, LABELS)
end

function LineLength:showPage()
    local ok, report, reason = pcall(pageReport, self.ui)
    if not ok then
        logger.warn("linelength: could not read the lines of this page:", report)
        UIManager:show(InfoMessage:new{ text = _("Could not read the lines of this page.") })
        return
    end
    if not report then
        UIManager:show(InfoMessage:new{
            text = reason == "unsupported" and _("This only works in books that reflow, like EPUB.")
                or _("There is no text on this page."),
        })
        return
    end
    showReport(report)
end

-- The page measurement as an action, so it can be put on a gesture, a quick action or a profile.
function LineLength:onDispatcherRegisterActions()
    -- The id "wordcount_page" is the plugin's old name. KOReader stores it in gesture and profile settings, so it
    -- stays: renaming it would silently unassign every gesture set up with 0.5.x or 0.6.x.
    -- rolling = only offered while a book that reflows is open (KOReader's own font actions do the same);
    -- in a PDF or in the file manager the action is not listed and does not run.
    Dispatcher:registerAction("wordcount_page", {
        category = "none", event = "LinelengthPage", title = _("Line length: this page"), rolling = true,
    })
end

function LineLength:onLinelengthPage()
    self:showPage()
    return true
end

function LineLength:addToMainMenu(menu_items)
    menu_items.linelength_page = {
        text = _("Line length: this page"),
        sorting_hint = "typeset",
        callback = function() self:showPage() end,
    }
end

function LineLength:init()
    -- Only in a book.
    if not self.document then
        return
    end
    self:onDispatcherRegisterActions()
    if self.ui and self.ui.menu then
        self.ui.menu:registerToMainMenu(self)
    end
    -- The selection button needs the highlight module; the page measurement does not.
    if not (self.ui and self.ui.highlight) then
        return
    end

    self.ui.highlight:addToHighlightDialog(SLOT, function(this)
        local c = countSelection(this)
        local tier = Rating.forChars(c.chars)
        return {
            text = T(_("Line: %1 chars · %2"), n(c.chars), LABELS[tier.id]),
            callback = function() showDetails(c) end,
        }
    end)
end

return LineLength
