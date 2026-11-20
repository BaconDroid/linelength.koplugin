-- Line length. Two ways in:
--  * select text: adds one button to the dialog (Select, Highlight, Copy, ...) that shows the length of
--    the selection in characters and how that reads as a line of text. Tap it for the details: characters
--    with and without spaces, words, and the ranges.
--  * the whole page: "Line length: this page" in the Typeset menu (also an action you can put on a gesture)
--    shows the longest lines on the page that is on screen, rated by the longest one.
local Device = require("device")
local Dispatcher = require("dispatcher")
local Event = require("ui/event")
local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local logger = require("logger")
local util = require("util")
local _ = require("gettext")
local T = require("ffi/util").template

local Counter = require("linelength/counter")
local Layout = require("linelength/layout")
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

-- `hooks` (optional, the page card only): { controls = which buttons are usable, values = what the steppers show,
-- on_control = function(card, id) }
local function showReport(report, hooks)
    -- The card is loaded on demand and guarded: whatever goes wrong with it, the button stays and
    -- the information is still shown.
    local ok, err = pcall(function()
        local Details = require("linelength/details")
        local card
        card = Details:new{
            report = report,
            use_color = colorEnabled(),
            controls = hooks and hooks.controls,
            values = hooks and hooks.values,
            on_control = hooks and hooks.controls and function(id) hooks.on_control(card, id) end,
        }
        UIManager:show(card)
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

-- Two reports say the same: the same longest line, and the same three lines in the same places.
local function sameReport(a, b)
    if a == nil or b == nil then
        return a == b
    end
    if a.chars ~= b.chars or #a.lines ~= #b.lines then
        return false
    end
    for i, line in ipairs(a.lines) do
        if line.number ~= b.lines[i].number or line.chars ~= b.lines[i].chars then
            return false
        end
    end
    return true
end

-- How many times the page is drawn and measured again, at most, to get a measurement that holds still.
local SETTLE_TRIES = 3

-- The report for the page on screen after the layout was changed (or when it may have changed).
-- KOReader renders only the chapter on screen when a setting changes ("partial rerendering": on by default for
-- EPUBs with several chapters, so a setting can be tried quickly) and does it when it next DRAWS the page. Until then
-- the lines are those of the old layout, and a measurement made right after the change is one change behind.
-- So when KOReader says the rendering is delayed, the page is drawn first, with KOReader's own paint (which does the
-- rendering and puts the page back where it was), and measured again until two measurements agree. When the book is
-- fully rendered by the time the change returns, there is nothing to wait for and nothing is drawn.
function LineLength:measureSettled()
    local report, reason = pageReport(self.ui)
    local ok, delayed = pcall(function() return self.ui.document:isRerenderingDelayed() end)
    if not (ok and delayed) then
        return report, reason
    end
    for _i = 1, SETTLE_TRIES do
        UIManager:forceRePaint()
        local again, again_reason = pageReport(self.ui)
        local settled = sameReport(report, again)
        report, reason = again, again_reason
        if settled then
            break
        end
    end
    return report, reason
end

-- The width of the screen in KOReader's "unscaled" units, the ones the margins and the font size are given in.
local function screenWidthUnits()
    local screen = Device.screen
    return screen:getWidth() / (screen:scaleBySize(100) / 100)
end

-- The margins and the font size the book is laid out with now, or nil when KOReader does not say.
function LineLength:currentLayout()
    local conf = self.ui and self.ui.document and self.ui.document.configurable
    local margins = conf and conf.h_page_margins
    local size = conf and conf.font_size
    if type(margins) == "table" and type(margins[1]) == "number" and type(margins[2]) == "number" and type(size) == "number" then
        return { margins = { margins[1], margins[2] }, size = size }
    end
    return nil
end

-- Which of the stepper buttons on the page card can be used now. nil (no buttons at all) when the layout is not known.
function LineLength:pageControls()
    local ok, controls = pcall(function()
        local layout = self:currentLayout()
        if not layout then
            return nil
        end
        return Layout.controls(layout, screenWidthUnits())
    end)
    return ok and controls or nil
end

-- What the steppers on the page card show: the margins and the text size as KOReader's own menus number them.
-- nil when the layout is not known.
function LineLength:pageValues()
    local ok, values = pcall(function()
        local layout = self:currentLayout()
        if not layout then
            return nil
        end
        return { margins = Layout.formatMargins(layout.margins), size = Layout.formatNumber(layout.size) }
    end)
    return ok and values or nil
end

-- Lays the book out again with new margins and/or a new text size, the way KOReader's own menu does it: a
-- ConfigChange (which is also what stores the value with the book) and then the event that sets it. Both are
-- sent straight to the reader: the card is a modal window and would swallow anything sent through UIManager.
function LineLength:applyLayout(margins, size)
    if margins then
        self.ui:handleEvent(Event:new("ConfigChange", "h_page_margins", margins))
        self.ui:handleEvent(Event:new("SetPageHorizMargins", margins))
    end
    if size then
        self.ui:handleEvent(Event:new("ConfigChange", "font_size", size))
        self.ui:handleEvent(Event:new("SetFontSize", size))
    end
end

-- Measures the page again and redraws the card with what it finds (if the page cannot be read the old numbers stay,
-- the buttons and the steppers still update).
function LineLength:redrawCard(card)
    local ok_report, report = pcall(function() return (self:measureSettled()) end)
    if not ok_report then
        logger.warn("linelength: could not read the lines of this page:", report)
        report = nil
    end
    card:update(report or card.report, self:pageControls(), self:pageValues())
end

-- A button on the page card was tapped: change the layout, measure the page again, redraw the card. "accept" changes
-- nothing: it measures the page again (it has been drawn by now) so the full card shows what the page really holds.
function LineLength:onControl(card, session, id)
    local ok, err = pcall(function()
        if id == "accept" then
            self:redrawCard(card)
            return
        end
        local layout = self:currentLayout()
        if not layout then
            return
        end
        local width = screenWidthUnits()
        local margins, size
        if id == "margins_less" then
            margins = Layout.stepMargins(layout.margins, -1, width)
        elseif id == "margins_more" then
            margins = Layout.stepMargins(layout.margins, 1, width)
        elseif id == "text_less" then
            size = Layout.stepFontSize(layout.size, -1)
        elseif id == "text_more" then
            size = Layout.stepFontSize(layout.size, 1)
        elseif id == "revert" or id == "cancel" then
            -- Puts the book back as it was when the card opened, whatever was changed since (also what was accepted).
            -- "revert" is the shrunk card's Cancel: the card stays and shows the page as it was. "cancel" is the full
            -- card's: the card closes itself afterwards.
            local before = session.baseline
            if not before then
                return
            end
            -- only what differs from now is set, so the book is not laid out again for nothing
            if before.margins[1] ~= layout.margins[1] or before.margins[2] ~= layout.margins[2] then
                margins = { before.margins[1], before.margins[2] }
            end
            if before.size ~= layout.size then
                size = before.size
            end
        else
            return
        end
        local restoring = id == "revert" or id == "cancel"
        if not restoring then
            if not (margins or size) then
                return -- at a limit
            end
            -- remembered before anything is changed, so Cancel can put it back even if the change fails half way
            session.baseline = session.baseline or layout
        end
        self:applyLayout(margins, size)
        if restoring then
            session.baseline = nil
        end
        if id == "cancel" then
            return -- the card is closing: nothing to measure or redraw
        end
        -- the page was laid out again: measure it again
        self:redrawCard(card)
    end)
    if not ok then
        logger.warn("linelength: could not change the layout:", err)
    end
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
    local session = {}
    showReport(report, {
        controls = self:pageControls(),
        values = self:pageValues(),
        on_control = function(card, id) self:onControl(card, session, id) end,
    })
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
