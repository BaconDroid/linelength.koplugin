-- End-to-end check of the margin / text size / undo buttons in a desktop build of KOReader: a REAL ReaderUI (the
-- real font, typeset and footer modules), the real main.lua, the real details card with its real buttons, and taps sent
-- through KOReader's own event system. Nothing about the layout is faked: a tap on a button has to change the real
-- margins and text size of the real book, and the card has to show the new measurement of the new page.
-- It models the code, not the Kaleido panel or the speed of the Kobo.
--   cd <KOReader.app>/Contents/koreader
--   HOME=<empty dir> PLUGIN_DIR=<this repo> BOOK=<an .epub> SHOT_DIR=<out dir> SDL_VIDEODRIVER=dummy \
--     EMULATE_READER_W=1264 EMULATE_READER_H=1680 EMULATE_READER_DPI=300 ./luajit <this repo>/tests/controls.lua
io.stdout:setvbuf("line")
os.setlocale("C", "numeric")
require("setupkoenv")
G_defaults = require("luadefaults"):open()
local DataStorage = require("datastorage")
G_reader_settings = require("luasettings"):open(DataStorage:getDataDir() .. "/settings.reader.lua")
local Device = require("device")
require("document/canvascontext"):init(Device)
require("ui/bidi").setup(nil)
local _bb = require("ffi/blitbuffer")
_bb:setUseCBB(true)
_bb:enableCBB(true)

local Event = require("ui/event")
local Geom = require("ui/geometry")
local UIManager = require("ui/uimanager")
local Screen = Device.screen
local util = require("util")

local PLUGIN = os.getenv("PLUGIN_DIR")
package.path = PLUGIN .. "/?.lua;" .. package.path
local PageLines = require("linelength/pagelines")

local failures = 0
local function check(name, ok, detail)
    print(string.format("%s  %s%s", ok and "PASS" or "FAIL", name, detail ~= nil and ("  (" .. tostring(detail) .. ")") or ""))
    if not ok then failures = failures + 1 end
end
local function pair(t) return t and (t[1] .. "," .. t[2]) or "nil" end

-- the real reader, with the real modules
local doc = require("document/documentregistry"):openDocument(os.getenv("BOOK"))
local ReaderUI = require("apps/reader/readerui")
local ui = ReaderUI:new{ dimen = Screen:getSize(), covers_fullscreen = true, document = doc }
ReaderUI.instance = ui
UIManager:show(ui)
UIManager:forceRePaint()
local conf = doc.configurable
print(string.format("book opened: margins %s, text size %s, %d pages; ReaderUI.postReaderReadyCallback=%s",
    pair(conf.h_page_margins), tostring(conf.font_size), doc:getPageCount(), tostring(ui.postReaderReadyCallback)))

-- the real plugin file, attached to this reader
local LineLength = dofile(PLUGIN .. "/main.lua")
local plugin = LineLength:new{ document = doc, ui = ui }

-- what the page really holds, measured here independently of the card
local function measure()
    local lines = PageLines.collect(doc, Screen:getWidth(), Screen:getHeight(), util.cleanupSelectedText)
    local top = PageLines.longest(lines, 3)
    return top[1] and top[1].chars or -1, #lines
end

-- the window on top of the stack
local function topWidget()
    local w = UIManager._window_stack[#UIManager._window_stack]
    return w and w.widget
end
local function onStack(widget)
    for _i, w in ipairs(UIManager._window_stack) do if w.widget == widget then return true end end
    return false
end
local function tapAt(x, y)
    UIManager:sendEvent(Event:new("Gesture", { ges = "tap", pos = Geom:new{ x = x, y = y, w = 0, h = 0 } }))
    UIManager:forceRePaint()
end
local function center(dimen) return dimen.x + dimen.w / 2, dimen.y + dimen.h / 2 end
local function tapButton(card, id)
    local button = card.buttons[id]
    local x, y = center(button.dimen)
    tapAt(x, y)
end
local FOUR = { "margins_less", "margins_more", "text_less", "text_more" }
local function enabledFlags(card)
    local s = {}
    for i, id in ipairs(FOUR) do
        s[i] = card.buttons[id].enabled and "1" or "0"
    end
    return table.concat(s)
end
-- every text the card draws (the labels of its buttons too), to see what is on it
local function texts(widget, found)
    found = found or {}
    if type(widget) ~= "table" then return found end
    if type(widget.text) == "string" then found[#found + 1] = widget.text end
    for _i, child in ipairs(widget) do texts(child, found) end
    return found
end
local function hasText(card, wanted)
    for _i, s in ipairs(texts(card)) do if s == wanted then return true end end
    return false
end
local function countTextsStartingWith(card, prefix)
    local n = 0
    for _i, s in ipairs(texts(card)) do if s:sub(1, #prefix) == prefix then n = n + 1 end end
    return n
end
-- where every button is on the screen, as one string. The last button is Done on the full card and Accept on the
-- shrunk one: it is in the same place, so it is listed as "confirm".
local PLACED = { "margins_less", "margins_more", "text_less", "text_more", "cancel", "confirm" }
local function places(card)
    local s = {}
    for i, id in ipairs(PLACED) do
        local d = (id == "confirm" and (card.buttons.done or card.buttons.accept) or card.buttons[id]).dimen
        s[i] = string.format("%s@%d,%d,%dx%d", id, d.x, d.y, d.w, d.h)
    end
    return table.concat(s, " ")
end
local ffiutil = require("ffi/util")
-- tasks on KOReader's scheduler that were scheduled by the card (the card must never schedule anything)
local function cardTasks()
    local n = 0
    for _i, t in ipairs(UIManager._task_queue) do
        local info = type(t.action) == "function" and debug.getinfo(t.action, "S")
        if info and info.source:find("linelength/details.lua", 1, true) then n = n + 1 end
    end
    return n
end
local function buttonLabels(card, ids)
    local labels = {}
    for i, id in ipairs(ids) do labels[i] = card.buttons[id] and card.buttons[id].text or "(none)" end
    return table.concat(labels, "|")
end

-- ---- 1. open the card the way the menu does
local start_chars, start_lines = measure()
local start_pages = doc:getPageCount()
local start_xp = doc:getXPointer()
print(string.format("start: longest line %d chars, %d lines, %d pages", start_chars, start_lines, start_pages))
local items = {}
plugin:addToMainMenu(items)
items.linelength_page.callback()
UIManager:forceRePaint()
local card = topWidget()
check("the menu item opened the page card", card ~= nil and card.report ~= nil and card.report.lines ~= nil)
check("the card shows the page's longest line", card.report.chars == start_chars, card.report.chars .. " vs " .. start_chars)
check("the card has its buttons", card.buttons.margins_more ~= nil and card.buttons.cancel ~= nil and card.buttons.done ~= nil)
check("all four steps are usable", enabledFlags(card) == "1111", enabledFlags(card))
check("Cancel and Done are always usable", card.buttons.cancel.enabled and card.buttons.done.enabled)
check("there is no Undo button", card.buttons.undo == nil and not hasText(card, "Undo"))
check("there is no Accept button on the full card", card.buttons.accept == nil)
check("the card opens full size", card.compact == false and hasText(card, "Longest lines on this page:"))
-- each button says what it does
check("the buttons are labelled − + − + Cancel Done", buttonLabels(card, { "margins_less", "margins_more", "text_less", "text_more", "cancel", "done" }) == "−|+|−|+|Cancel|Done",
    buttonLabels(card, { "margins_less", "margins_more", "text_less", "text_more", "cancel", "done" }))
check("the steppers are named Margins and Text size", hasText(card, "Margins") and hasText(card, "Text size"))
check("the steppers show the real values (10 and 22)", hasText(card, "10") and hasText(card, "22"))
-- the first number after a label is that row's value (the texts come in the order they are drawn)
local function valueAfter(card_, label)
    local seen = false
    for _i, s in ipairs(texts(card_)) do
        if seen and s:match("^%d[%d%./]*$") then return s end
        if s == label then seen = true end
    end
end
check("the Margins row shows the margins (10) and the Text size row the size (22)", valueAfter(card, "Margins") == "10" and valueAfter(card, "Text size") == "22",
    tostring(valueAfter(card, "Margins")) .. " / " .. tostring(valueAfter(card, "Text size")))
-- a redraw is asked for every time the card is updated: count the requests made by ONE call of update (during a
-- tap KOReader itself asks for redraws too, which would hide a card that does not ask)
local redraws = 0
local real_setDirty = UIManager.setDirty
UIManager.setDirty = function(self, ...)
    redraws = redraws + 1
    return real_setDirty(self, ...)
end
check("the buttons were painted (they have a place on the screen)", card.buttons.margins_more.dimen.w > 0)
local open_places = places(card)
local open_y, open_h = card.frame.dimen.y, card.frame.dimen.h
Screen:shot((os.getenv("SHOT_DIR") or ".") .. "/controls_1_open.png")

-- ---- 2. a tap on "Margins +": wider margins, shorter lines
local t0 = os.clock()
tapButton(card, "margins_more")
local took = os.clock() - t0
-- Details:update by itself: it asks for a redraw (of the whole screen, the page behind has changed too), and it
-- keeps the report and the button states it is given
local redraws_before = redraws
local kept_report, kept_controls = card.report, card.controls
card:update(kept_report, kept_controls)
check("Details:update asks the screen for a redraw", redraws > redraws_before, redraws - redraws_before)
check("Details:update keeps the report it was given", card.report == kept_report)
check("Details:update keeps the button states it was given", card.controls == kept_controls)
local other_controls = { margins_less = false, margins_more = true, text_less = true, text_more = false }
card:update(kept_report, other_controls)
check("Details:update shows the new button states", enabledFlags(card) == "0110", enabledFlags(card))
card:update(kept_report) -- no states given: the last ones stay
check("Details:update without states keeps the last ones", enabledFlags(card) == "0110", enabledFlags(card))
card:update(kept_report, kept_controls)
check("and they can be set back", enabledFlags(card) == "1111", enabledFlags(card))
UIManager:forceRePaint() -- the rebuilt buttons get their place on the screen when they are painted
local m1 = conf.h_page_margins
-- 1264 px / (211 px per 100 units) = 599.05 units; text = 599.05 - 20 = 579.05; 2.5% = 14.48 -> 14 each side
check("margins +: the real margins moved by one step (10 -> 24 each side)", pair(m1) == "24,24", pair(m1))
check("margins +: KOReader's typeset module has them too", pair({ ui.typeset.unscaled_margins[1], ui.typeset.unscaled_margins[3] }) == "24,24",
    table.concat(ui.typeset.unscaled_margins, ","))
local c1, l1 = measure()
check("margins +: the lines got shorter", c1 < start_chars, start_chars .. " -> " .. c1)
check("margins +: the card shows what the page really measures now", card.report.chars == c1, card.report.chars .. " vs " .. c1)
check("margins +: the card is still on screen, shrunk", onStack(card) and card.compact == true)
check("margins +: all four steps still usable", enabledFlags(card) == "1111", enabledFlags(card))
local lines_now = PageLines.collect(doc, Screen:getWidth(), Screen:getHeight(), util.cleanupSelectedText)
local top_now = PageLines.longest(lines_now, 3)
local listed_ok = #card.report.lines == #top_now
for i, l in ipairs(card.report.lines) do
    listed_ok = listed_ok and top_now[i] and l.number == top_now[i].number and l.chars == top_now[i].chars
end
check("margins +: the three listed lines (numbers and lengths) are the page's own", listed_ok)
print(string.format("  margins +: longest %d -> %d, pages %d -> %d, took %.3f s", start_chars, c1, start_pages, doc:getPageCount(), took))
Screen:shot((os.getenv("SHOT_DIR") or ".") .. "/controls_2_margins_more.png")

-- ---- 3. a tap on "Text +": bigger text, shorter lines. 22 -> 23 (5% of 22 is 1.1 -> 1)
tapButton(card, "text_more")
check("text +: the real font size moved by one step (22 -> 23)", conf.font_size == 23, conf.font_size)
local c2 = measure()
check("text +: lines are shorter still", c2 < c1, c1 .. " -> " .. c2)
check("text +: the card shows what the page really measures now", card.report.chars == c2, card.report.chars .. " vs " .. c2)
check("text +: the card is still on screen", onStack(card))

-- ---- 4. what was changed is stored with the book (KOReader saves `configurable` as copt_* settings)
ui:handleEvent(Event:new("SaveSettings"))
local saved_size = ui.doc_settings:readSetting("copt_font_size")
local saved_margins = ui.doc_settings:readSetting("copt_h_page_margins")
check("stored with the book: font size", saved_size == 23, tostring(saved_size))
check("stored with the book: margins", pair(saved_margins) == "24,24", pair(saved_margins))

-- ---- 5. "Margins −" and "Text −": the other direction
tapButton(card, "margins_less")
local m2 = conf.h_page_margins
-- from 24/24: text = 599.05 - 48 = 551.05; 13.78 -> 14 -> back to 10/10
check("margins −: back to 10 each side", pair(m2) == "10,10", pair(m2))
tapButton(card, "text_less")
-- from 23: 5% is 1.15 -> 1 -> 22
check("text −: back to 22", conf.font_size == 22, conf.font_size)
local c3 = measure()
check("by hand back to the original layout: the page measures as at the start", c3 == start_chars, start_chars .. " vs " .. c3)
check("by hand back: the card shows it", card.report.chars == c3)

-- ---- 6. Cancel on the shrunk card, after changing both: everything is back as it was when the card OPENED, and the
-- card is full size again
tapButton(card, "margins_more")
tapButton(card, "text_more")
tapButton(card, "text_more")
check("before Cancel: the layout is changed (margins 24, size 24) and the card is shrunk", pair(conf.h_page_margins) == "24,24" and conf.font_size == 24 and card.compact == true,
    pair(conf.h_page_margins) .. " / " .. tostring(conf.font_size))
check("the shrunk card has Cancel and Accept at the bottom", buttonLabels(card, { "cancel", "accept" }) == "Cancel|Accept" and card.buttons.done == nil)
tapButton(card, "cancel")
check("Cancel on the shrunk card: the real margins are as at the start", pair(conf.h_page_margins) == "10,10", pair(conf.h_page_margins))
check("Cancel on the shrunk card: the real text size is as at the start", conf.font_size == 22, conf.font_size)
check("Cancel on the shrunk card: the typeset module is back to the start too", ui.typeset.unscaled_margins[1] == 10 and ui.typeset.unscaled_margins[3] == 10)
local c4 = measure()
check("Cancel on the shrunk card: the page measures as at the start", c4 == start_chars, start_chars .. " vs " .. c4)
check("Cancel on the shrunk card: the same number of pages as at the start", doc:getPageCount() == start_pages, start_pages .. " vs " .. doc:getPageCount())
check("Cancel on the shrunk card: the same place in the book (page top)", doc:getXPointer() == start_xp, start_xp .. " vs " .. tostring(doc:getXPointer()))
check("Cancel on the shrunk card: the card stays open", onStack(card))
check("Cancel on the shrunk card: it is full size again, with the page as at the start", card.compact == false and hasText(card, "Longest lines on this page:") and card.report.chars == start_chars)
check("Cancel on the shrunk card: the steppers show 10 and 22 again", valueAfter(card, "Margins") == "10" and valueAfter(card, "Text size") == "22",
    tostring(valueAfter(card, "Margins")) .. " / " .. tostring(valueAfter(card, "Text size")))
check("Cancel on the shrunk card: the full card has Cancel and Done again", buttonLabels(card, { "cancel", "done" }) == "Cancel|Done" and card.buttons.accept == nil)
UIManager:forceRePaint()
check("Cancel on the shrunk card: the buttons are where they were when the card opened", places(card) == open_places, places(card) .. " | " .. open_places)
check("Cancel on the shrunk card: all four steps usable", enabledFlags(card) == "1111", enabledFlags(card))

-- ---- 7. taps on the card that are not on a button, and taps outside
local bx, by = center(card.titlebar.dimen)
tapAt(bx - 200, by) -- the title text: inside the card, not a button
check("a tap inside the card, off the buttons, does not close it", onStack(card))
tapAt(5, 5) -- far outside the card
check("a tap outside the card closes it", not onStack(card))
check("a tap outside the card left the layout alone", pair(conf.h_page_margins) == "10,10" and conf.font_size == 22)

-- ---- 8. a disabled button does nothing
conf.h_page_margins = { 140, 140 } -- as if the user had set them there
ui:handleEvent(Event:new("SetPageHorizMargins", { 140, 140 }))
items.linelength_page.callback()
UIManager:forceRePaint()
card = topWidget()
check("at margins 140/140 'Margins +' is off", not card.buttons.margins_more.enabled and card.buttons.margins_less.enabled,
    enabledFlags(card))
local doc_margins_before = pair(conf.h_page_margins)
tapButton(card, "margins_more")
check("tapping the disabled button changes nothing", pair(conf.h_page_margins) == doc_margins_before and onStack(card))
check("a tap on a disabled button does not shrink the card", card.compact == false)
-- the X still closes it
local xb = card.titlebar.right_button
local xx, xy = center(xb.dimen)
tapAt(xx, xy)
check("the X closes the card", not onStack(card))
conf.h_page_margins = { 10, 10 }
ui:handleEvent(Event:new("SetPageHorizMargins", { 10, 10 }))

-- ---- 8b. the flow: tap a stepper, the card shrinks and STAYS small (no timer), Accept or Cancel bring the full card back
local function openCard()
    items.linelength_page.callback()
    UIManager:forceRePaint()
    return topWidget()
end
local function setLayout(margin, size)
    ui:handleEvent(Event:new("ConfigChange", "h_page_margins", { margin, margin }))
    ui:handleEvent(Event:new("SetPageHorizMargins", { margin, margin }))
    ui:handleEvent(Event:new("ConfigChange", "font_size", size))
    ui:handleEvent(Event:new("SetFontSize", size))
end
local SHOTS = os.getenv("SHOT_DIR") or "."
card = openCard()
local full_places = places(card)
local full_y, full_h = card.frame.dimen.y, card.frame.dimen.h
-- the air between the Text size stepper and the Cancel / Done buttons, and between the two steppers (pixels from the
-- bottom of one row of buttons to the top of the next)
local function actionsGap(c)
    local above, below = c.buttons.text_more.dimen, c.buttons.cancel.dimen
    return below.y - (above.y + above.h)
end
local function steppersGap(c)
    local above, below = c.buttons.margins_more.dimen, c.buttons.text_more.dimen
    return below.y - (above.y + above.h)
end
local full_actions_gap, full_steppers_gap = actionsGap(card), steppersGap(card)
check("full size: there is air between the Text size stepper and the buttons (at least 12 units)", full_actions_gap >= Screen:scaleBySize(12), full_actions_gap)
check("full size: more air above the buttons than between the two steppers", full_actions_gap > full_steppers_gap, full_actions_gap .. " vs " .. full_steppers_gap)
check("full size: on the screen, and the card has scheduled nothing", onStack(card) and cardTasks() == 0)
check("full size: the same place as every other time it opened", full_places == open_places and full_y == open_y and full_h == open_h)

tapButton(card, "text_more") -- 22 -> 23
check("a tap on a stepper shrinks the card", card.compact == true)
check("shrunk: the list of lines and the four ranges are gone",
    not hasText(card, "Longest lines on this page:") and countTextsStartingWith(card, "○") + countTextsStartingWith(card, "●") == 0)
check("shrunk: the title, the number, its caption and the verdict stay",
    hasText(card, "Line length") and hasText(card, tostring(card.report.chars)) and hasText(card, "characters in the longest line") and hasText(card, card.report.tier.label))
check("shrunk: both steppers stay, with the new value (23)", hasText(card, "Margins") and hasText(card, "Text size") and hasText(card, "23"))
check("shrunk: the bottom row is Cancel and Accept (no Done, no Undo)",
    buttonLabels(card, { "cancel", "accept" }) == "Cancel|Accept" and card.buttons.done == nil and card.buttons.undo == nil and not hasText(card, "Undo") and not hasText(card, "Done"))
check("shrunk: Cancel and Accept are always usable", card.buttons.cancel.enabled and card.buttons.accept.enabled)
check("shrunk: each row shows its own value (margins 10, size 23)", valueAfter(card, "Margins") == "10" and valueAfter(card, "Text size") == "23",
    tostring(valueAfter(card, "Margins")) .. " / " .. tostring(valueAfter(card, "Text size")))
check("shrunk: the card is smaller", card.frame.dimen.h < full_h, card.frame.dimen.h .. " vs " .. full_h)
check("shrunk: it keeps the bottom edge of the full card", math.abs(card.frame.dimen.y + card.frame.dimen.h - (full_y + full_h)) <= 1,
    (card.frame.dimen.y + card.frame.dimen.h) .. " vs " .. (full_y + full_h))
check("shrunk: so more of the page shows (the card starts lower)", card.frame.dimen.y > full_y, card.frame.dimen.y .. " vs " .. full_y)
check("shrunk: every button is exactly where it was", places(card) == full_places, places(card) .. " | " .. full_places)
check("shrunk: the same air above the buttons as on the full card", actionsGap(card) == full_actions_gap, actionsGap(card) .. " vs " .. full_actions_gap)
check("shrunk: and the same gap between the two steppers", steppersGap(card) == full_steppers_gap, steppersGap(card) .. " vs " .. full_steppers_gap)
Screen:shot(SHOTS .. "/controls_4_shrunk.png")

-- no timer: the card scheduled nothing, and a pause of more than a second changes nothing
check("shrunk: the card has scheduled nothing", cardTasks() == 0)
ffiutil.usleep(1250000)
UIManager:_checkTasks()
check("shrunk: after 1.25 s without a tap it is still shrunk", card.compact == true and onStack(card))
local tx, ty = center(card.titlebar.dimen)
tapAt(tx - 200, ty) -- the title text of the shrunk card: inside it, on no button
check("shrunk: a tap inside the card off the buttons does nothing", onStack(card) and card.compact == true)

-- more taps: still shrunk, the buttons do not move
tapButton(card, "text_more") -- 23 -> 24
check("a second tap: still shrunk", card.compact == true)
check("a second tap: the buttons did not move", places(card) == full_places)
tapButton(card, "margins_more") -- 10 -> 24
check("a third tap (the other stepper): still shrunk, margins now 24", card.compact == true and pair(conf.h_page_margins) == "24,24" and conf.font_size == 24)

-- Accept: the changes stay and the full card is back with the latest numbers
local redraws_before_accept = redraws
tapButton(card, "accept")
UIManager:forceRePaint()
check("Accept: full size again", card.compact == false and hasText(card, "Longest lines on this page:"))
check("Accept: the screen was asked to redraw", redraws > redraws_before_accept, redraws - redraws_before_accept)
check("Accept: the layout is kept (margins 24, size 24)", pair(conf.h_page_margins) == "24,24" and conf.font_size == 24, pair(conf.h_page_margins) .. " / " .. tostring(conf.font_size))
check("Accept: the card shows what the page measures now", card.report.chars == measure())
check("Accept: the steppers show 24 and 24", valueAfter(card, "Margins") == "24" and valueAfter(card, "Text size") == "24",
    tostring(valueAfter(card, "Margins")) .. " / " .. tostring(valueAfter(card, "Text size")))
check("Accept: the card is still on the screen", onStack(card))
check("Accept: Cancel and Done are back at the bottom", buttonLabels(card, { "cancel", "done" }) == "Cancel|Done" and card.buttons.accept == nil)
check("Accept: the buttons are where they were", places(card) == full_places, places(card) .. " | " .. full_places)
check("Accept: the same air above the buttons as before", actionsGap(card) == full_actions_gap, actionsGap(card) .. " vs " .. full_actions_gap)
check("Accept: the card has scheduled nothing", cardTasks() == 0)
Screen:shot(SHOTS .. "/controls_5_full_again.png")
-- a plain update (not caused by a button) redraws the card at the size it has, it does not shrink it
card:update(card.report)
UIManager:forceRePaint()
check("a plain update does not shrink a full size card", card.compact == false)

-- tap again after Accept, then Cancel: back to how it was when the popup OPENED (also what was accepted)
tapButton(card, "text_less") -- 24 -> 23
check("after Accept a tap shrinks the card again", card.compact == true and conf.font_size == 23)
tapButton(card, "cancel")
check("Cancel after an Accept: back to when the popup opened (margins 10, size 22)", pair(conf.h_page_margins) == "10,10" and conf.font_size == 22,
    pair(conf.h_page_margins) .. " / " .. tostring(conf.font_size))
check("Cancel after an Accept: the card is full size and shows the start", card.compact == false and card.report.chars == start_chars and onStack(card))
check("Cancel after an Accept: the same place in the book (page top)", doc:getXPointer() == start_xp, start_xp .. " vs " .. tostring(doc:getXPointer()))
UIManager:forceRePaint()
-- and the card goes on working: a new round, then Accept, then Done keeps it
tapButton(card, "margins_more")
check("a new round after Cancel: shrunk, margins 24", card.compact == true and pair(conf.h_page_margins) == "24,24")
tapButton(card, "accept")
UIManager:forceRePaint()
check("a new round after Cancel: Accept shows the full card", card.compact == false and onStack(card))
tapButton(card, "done")
check("Done closes the card", not onStack(card))
check("Done keeps the changes (margins 24, size 22)", pair(conf.h_page_margins) == "24,24" and conf.font_size == 22, pair(conf.h_page_margins) .. " / " .. tostring(conf.font_size))
setLayout(10, 22)

-- a tap outside while shrunk closes the card and keeps what was changed (like Done)
card = openCard()
tapButton(card, "text_more")
check("outside tap: the card is shrunk and the size is 23", card.compact == true and conf.font_size == 23)
tapAt(5, 5)
check("a tap outside while shrunk closes the card", not onStack(card))
check("a tap outside while shrunk keeps what was changed", conf.font_size == 23)
setLayout(10, 22)

-- the X, while shrunk: the changes stay
card = openCard()
tapButton(card, "margins_more")
check("X: the card is shrunk and the margins changed (24)", card.compact == true and pair(conf.h_page_margins) == "24,24", pair(conf.h_page_margins))
local x_button = card.titlebar.right_button
tapAt(center(x_button.dimen))
check("X while shrunk closes the card", not onStack(card))
check("X keeps what was changed", pair(conf.h_page_margins) == "24,24")
setLayout(10, 22)

-- Cancel on the full card: everything is put back as it was when the card opened, and the card closes
card = openCard()
tapButton(card, "margins_more")
tapButton(card, "text_more")
tapButton(card, "text_more")
tapButton(card, "accept")
UIManager:forceRePaint()
check("before Cancel on the full card: the layout is changed (margins 24, size 24)", pair(conf.h_page_margins) == "24,24" and conf.font_size == 24 and card.compact == false)
tapButton(card, "cancel")
check("Cancel on the full card closes it", not onStack(card))
check("Cancel on the full card: the real margins are as at the start", pair(conf.h_page_margins) == "10,10", pair(conf.h_page_margins))
check("Cancel on the full card: the real text size is as at the start", conf.font_size == 22, conf.font_size)
check("Cancel on the full card: the typeset module is back too", ui.typeset.unscaled_margins[1] == 10 and ui.typeset.unscaled_margins[3] == 10)
check("Cancel on the full card: the page measures as at the start", measure() == start_chars, start_chars .. " vs " .. measure())
check("Cancel on the full card: the same number of pages", doc:getPageCount() == start_pages)
check("Cancel on the full card: the same place in the book (page top)", doc:getXPointer() == start_xp, start_xp .. " vs " .. tostring(doc:getXPointer()))
ui:handleEvent(Event:new("SaveSettings"))
check("Cancel on the full card: what is stored with the book is as at the start too", ui.doc_settings:readSetting("copt_font_size") == 22 and pair(ui.doc_settings:readSetting("copt_h_page_margins")) == "10,10")

-- Cancel on the full card with nothing changed: just closes
card = openCard()
tapButton(card, "cancel")
check("Cancel with nothing changed closes the card and changes nothing", not onStack(card) and pair(conf.h_page_margins) == "10,10" and conf.font_size == 22)
check("nothing is left on KOReader's scheduler by the card", cardTasks() == 0)

-- ---- 9. the card on its own, with a stub for what the plugin does: which id each button sends, and what closes
local Details = require("linelength/details")
local Report = require("linelength/report")
local LABELS = { too_long = "Too long", still_readable = "Still readable", comfortable = "Comfortable", excellent = "Excellent", short = "Short" }
local CTRL = { margins_less = true, margins_more = true, text_less = true, text_more = true }
local REPORT = Report.build({ chars = 58, chars_no_spaces = 50, words = 10 }, LABELS)
local closed = {}
local real_close = UIManager.close
UIManager.close = function(self_, widget, ...)
    closed[widget] = (closed[widget] or 0) + 1
    return real_close(self_, widget, ...)
end
local function stubCard(compact, redraw)
    local got = {}
    local c
    c = Details:new{ report = REPORT, controls = CTRL, values = { margins = "10", size = "22" }, compact = compact, on_control = function(id)
        got[#got + 1] = id
        if redraw then c:update(c.report) end
    end }
    c.got = got
    return c
end
-- a stepper tap asks the plugin for it by its own id; the plugin that does not redraw leaves the card as it is
local quiet = stubCard(false, false)
quiet:press("text_more")
check("a stepper sends its own id to the plugin", table.concat(quiet.got, ",") == "text_more", table.concat(quiet.got, ","))
check("an action that does not redraw: the card does not shrink", quiet.compact == false)
local noisy = stubCard(false, true)
noisy:press("text_more")
check("an action that redraws: the card shrinks", noisy.compact == true)
noisy:press("not_a_button")
check("an id that does not change the layout does not shrink a full card", stubCard(false, true).compact == false and (function() local c = stubCard(false, true) c:press("not_a_button") return c.compact end)() == false)
-- Cancel
local full_cancel = stubCard(false, true)
full_cancel:press("cancel")
check("Cancel on the full card asks the plugin to cancel", table.concat(full_cancel.got, ",") == "cancel", table.concat(full_cancel.got, ","))
check("Cancel on the full card closes it", closed[full_cancel] == 1, tostring(closed[full_cancel]))
local small_cancel = stubCard(true, true)
small_cancel:press("cancel")
check("Cancel on the shrunk card asks the plugin to revert", table.concat(small_cancel.got, ",") == "revert", table.concat(small_cancel.got, ","))
check("Cancel on the shrunk card does not close it", closed[small_cancel] == nil)
check("Cancel on the shrunk card, redrawn by the plugin: full size again", small_cancel.compact == false)
local stuck_cancel = stubCard(true, false)
stuck_cancel:press("cancel")
check("Cancel on the shrunk card, plugin did not redraw: stays shrunk and open", stuck_cancel.compact == true and closed[stuck_cancel] == nil)
-- Accept asks the plugin to measure the page again (what the shrunk card showed can be one change behind), then shows
-- the full card, also when the plugin could not measure. Done never involves the plugin.
local accept = stubCard(true, true)
accept:press("accept")
check("Accept: the plugin is asked to measure again", table.concat(accept.got, ",") == "accept", table.concat(accept.got, ","))
check("Accept: full size, the card stays open", accept.compact == false and closed[accept] == nil)
-- the card is rebuilt once for Accept (a second build would be a second refresh of the screen for nothing)
local counted = stubCard(true, true)
local builds = 0
local real_build = counted.build
counted.build = function(self_, ...) builds = builds + 1; return real_build(self_, ...) end
counted:press("accept")
check("Accept rebuilds the card once, not twice", builds == 1, builds)
local accept_quiet = stubCard(true, false)
check("(before Accept the shrunk card does not have the counts)", not hasText(accept_quiet, "With spaces"))
local redraws_quiet = redraws
accept_quiet:press("accept")
check("Accept: the plugin did not redraw: still the full card, still open", accept_quiet.compact == false and closed[accept_quiet] == nil and table.concat(accept_quiet.got, ",") == "accept")
check("Accept: the plugin did not redraw: the card itself was rebuilt full (it has the counts again)", hasText(accept_quiet, "With spaces") and accept_quiet.buttons.done ~= nil and accept_quiet.buttons.accept == nil)
check("Accept: the plugin did not redraw: the screen was asked to redraw", redraws > redraws_quiet, redraws - redraws_quiet)
local accept_failing
accept_failing = Details:new{ report = REPORT, controls = CTRL, values = { margins = "10", size = "22" }, compact = true, on_control = function() error("plugin boom") end }
local ok_accept, err_accept = pcall(accept_failing.press, accept_failing, "accept")
check("Accept: a plugin that fails: the card is full size anyway, and the error is not swallowed",
    accept_failing.compact == false and ok_accept == false and tostring(err_accept):find("plugin boom", 1, true) ~= nil, tostring(err_accept))
local accept_full = stubCard(false, true)
accept_full:press("accept")
check("Accept on a full card: stays full and open", accept_full.compact == false and closed[accept_full] == nil)
local done = stubCard(false, true)
done:press("done")
check("Done: closes the card, the plugin is not asked", closed[done] == 1 and #done.got == 0)
local done_small = stubCard(true, true)
done_small:press("done")
check("Done also closes a shrunk card", closed[done_small] == 1)
-- a plugin that fails: the error reaches the caller, and the card is not left half way (flags cleared)
local failing
failing = Details:new{ report = REPORT, controls = CTRL, values = { margins = "10", size = "22" }, on_control = function() error("plugin boom") end }
local ok_press, err_press = pcall(failing.press, failing, "text_more")
check("a plugin that fails: the error is not swallowed by the card", ok_press == false and tostring(err_press):find("plugin boom", 1, true) ~= nil, tostring(err_press))
failing.on_control = function() failing:update(failing.report) end
failing:press("not_a_button")
check("a plugin that failed once does not leave the card shrinking on its own", failing.compact == false)
failing:update(failing.report)
check("... nor on a later plain update", failing.compact == false)
-- the card of a page without controls keeps closing on any tap and never shrinks
local plain = Details:new{ report = REPORT }
plain:press("text_more")
check("a card without controls does not shrink", plain.compact == false and plain.buttons.cancel == nil)
-- a tap that arrives before the card was painted (it has no place on the screen yet) is not a tap outside of it
local before_paint = stubCard(false, true)
local handled = before_paint:onTapClose(nil, { pos = Geom:new{ x = 5, y = 5, w = 0, h = 0 } })
check("a tap before the first paint does not close the card and does not fail", handled == true and closed[before_paint] == nil, tostring(handled) .. " / " .. tostring(closed[before_paint]))
UIManager.close = real_close

local sel = Details:new{ report = REPORT }
UIManager:show(sel)
UIManager:forceRePaint()
check("the selection card has no buttons", next(sel.buttons) == nil)
local sx, sy = center(sel.titlebar.dimen)
tapAt(sx - 200, sy) -- inside the card
check("the selection card still closes on a tap anywhere", not onStack(sel))

-- ---- 10. the whole thing again from the gesture action, on a different page. The page is changed the way a reader
-- changes it (KOReader's own GotoPage event), so the reader keeps track of where it is: moving the document behind
-- its back would make it jump back to its old place when the layout changes.
ui:handleEvent(Event:new("GotoPage", 3))
UIManager:forceRePaint()
local mid_chars = measure()
local mid_xp, mid_pages = doc:getXPointer(), doc:getPageCount()
check("page 3 is the current page", doc:getCurrentPage() == 3, doc:getCurrentPage())
plugin:onLinelengthPage()
UIManager:forceRePaint()
card = topWidget()
check("page 3: the card opens with the buttons", card ~= nil and card.buttons.margins_more ~= nil and card.report.chars == mid_chars)
tapButton(card, "margins_more")
local c5 = measure()
check("page 3: a tap measures that page again", card.report.chars == c5, card.report.chars .. " vs " .. c5)
check("page 3: the layout changed (one more page in the book)", doc:getPageCount() == mid_pages + 1, mid_pages .. " -> " .. doc:getPageCount())
check("page 3: the reader keeps its place in the text (the anchor does not move)", ui.rolling.xpointer == mid_xp, tostring(ui.rolling.xpointer))
tapButton(card, "cancel")
check("page 3: Cancel gives the margins back", pair(conf.h_page_margins) == "10,10")
check("page 3: Cancel gives the page back as it was (same measure)", measure() == mid_chars, mid_chars .. " vs " .. measure())
check("page 3: Cancel gives the same page top, to the character", doc:getXPointer() == mid_xp, tostring(doc:getXPointer()))
check("page 3: Cancel gives the same number of pages", doc:getPageCount() == mid_pages)
check("page 3: and the same page number", doc:getCurrentPage() == 3, doc:getCurrentPage())
check("page 3: the card is full size again and shows the page as it was", card.compact == false and card.report.chars == mid_chars and onStack(card))
Screen:shot((os.getenv("SHOT_DIR") or ".") .. "/controls_3_page3_cancelled.png")
UIManager:close(card)
UIManager:forceRePaint()

if failures > 0 then print(failures .. " FAILURE(S)"); os.exit(1) end
print("all checks passed")
os.exit(0)
