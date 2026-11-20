-- End-to-end check with a book KOReader renders PARTIALLY: an EPUB with several chapters, with "partial rerendering" on
-- (KOReader's default). After a change of the margins or the text size KOReader re-renders only the chapter on screen,
-- and only when it next DRAWS the page. A measurement made right after the change is one change behind; the card must
-- show what the page holds once drawn, at every tap and after Accept, and the reopened card must say the same.
-- Real ReaderUI, real main.lua, real card, real taps. It models the code, not the Kaleido panel or the speed of the Kobo.
--   python3 tests/fixtures/make_epub_chapters.py <dir>/chapters 10 40      (a book over 64 KB: below that crengine makes
--                                                                           no cache and cannot render partially)
--   cd <KOReader.app>/Contents/koreader
--   HOME=<empty dir> PLUGIN_DIR=<this repo> BOOK=<dir>/chapters.epub SHOT_DIR=<out dir> SDL_VIDEODRIVER=dummy \
--     EMULATE_READER_W=1264 EMULATE_READER_H=1680 EMULATE_READER_DPI=300 ./luajit <this repo>/tests/partial.lua
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

local doc = require("document/documentregistry"):openDocument(os.getenv("BOOK"))
local ReaderUI = require("apps/reader/readerui")
local ui = ReaderUI:new{ dimen = Screen:getSize(), covers_fullscreen = true, document = doc }
ReaderUI.instance = ui
UIManager:show(ui)
UIManager:forceRePaint()
check("the book can be rendered partially (several chapters, big enough for a cache)", doc:canBePartiallyRerendered() == true)
-- what ReaderRolling:onReaderReady does one UI tick after the reader is ready (this test does not run the UI loop)
doc:enablePartialRerendering(true)
ui.rolling.partial_rerendering = doc:isPartialRerenderingEnabled()
check("partial rerendering is on", doc:isPartialRerenderingEnabled() == true)
local conf = doc.configurable
-- VIEW_MODE=scroll runs the whole test in continuous (scroll) view, where the reader paints the page differently
if os.getenv("VIEW_MODE") then
    ui:handleEvent(Event:new("SetViewMode", os.getenv("VIEW_MODE")))
    UIManager:forceRePaint()
    check("the view mode is " .. os.getenv("VIEW_MODE"), ui.view.view_mode == os.getenv("VIEW_MODE"), ui.view.view_mode)
end

local LineLength = dofile(PLUGIN .. "/main.lua")
local plugin = LineLength:new{ document = doc, ui = ui }
local items = {}
plugin:addToMainMenu(items)

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
local function tapButton(card, id)
    local d = card.buttons[id].dimen
    tapAt(d.x + d.w / 2, d.y + d.h / 2)
end
local function openCard()
    items.linelength_page.callback()
    UIManager:forceRePaint()
    return topWidget()
end

-- What the page holds once the screen has been drawn and KOReader has had its ticks: the ground truth. (Drawing is
-- what renders a partially rendered book, so this is also what the reader would show.)
local function settled()
    for _i = 1, 4 do
        UIManager:forceRePaint()
        UIManager:_checkTasks()
    end
    local lines = PageLines.collect(doc, Screen:getWidth(), Screen:getHeight(), util.cleanupSelectedText)
    local top = PageLines.longest(lines, 3)
    local parts = {}
    for _i, l in ipairs(top) do parts[#parts + 1] = l.number .. ":" .. l.chars end
    return top[1] and top[1].chars or -1, table.concat(parts, " ")
end
local function cardLines(card)
    local parts = {}
    for _i, l in ipairs(card.report.lines) do parts[#parts + 1] = l.number .. ":" .. l.chars end
    return table.concat(parts, " ")
end

-- a page in the second chapter
ui:handleEvent(Event:new("GotoPage", 20))
UIManager:forceRePaint()
local start_chars, start_lines = settled()
local start_xp = doc:getXPointer()
print(string.format("start: page %d, longest line %d chars (%s), delayed=%s", doc:getCurrentPage(), start_chars, start_lines, tostring(doc:isRerenderingDelayed())))

-- ---- 1. every step: the card shows what the page holds once drawn (the plugin used to show the previous step's)
local card = openCard()
check("the card opens with the page as it is (the longest line)", card.report.chars == start_chars, card.report.chars .. " vs " .. start_chars)
local STEPS = { "margins_more", "text_more", "margins_more", "text_less", "margins_less", "text_more", "margins_more", "margins_more" }
local stale = 0
local last_card, last_truth
for i, id in ipairs(STEPS) do
    tapButton(card, id)
    local shown_chars, shown_lines = card.report.chars, cardLines(card)
    local truth_chars, truth_lines = settled()
    local ok = shown_chars == truth_chars and shown_lines == truth_lines
    if not ok then stale = stale + 1 end
    check(string.format("step %d (%s): the card shows what the page holds once drawn", i, id), ok,
        string.format("card %d [%s] vs page %d [%s]", shown_chars, shown_lines, truth_chars, truth_lines))
    last_card, last_truth = shown_chars, truth_chars
end
check("no step showed the numbers of the step before", stale == 0, stale .. " stale")
check("the book really was rendered partially while this went on", doc:isRerenderingDelayed() == true)
check("the card is shrunk and still on the screen", card.compact == true and onStack(card))
check("the layout really changed (not the one it started with)", pair(conf.h_page_margins) ~= "10,10" or conf.font_size ~= 22,
    pair(conf.h_page_margins) .. " / " .. tostring(conf.font_size))

-- ---- 2. Accept measures again, shows the full card, and the numbers hold
local before_accept = card.report.chars
tapButton(card, "accept")
local truth_after_accept, truth_lines_after = settled()
check("Accept: the full card is back", card.compact == false and onStack(card))
check("Accept: it shows what the page holds", card.report.chars == truth_after_accept and cardLines(card) == truth_lines_after,
    card.report.chars .. " [" .. cardLines(card) .. "] vs " .. truth_after_accept .. " [" .. truth_lines_after .. "]")
local accepted_chars, accepted_lines = card.report.chars, cardLines(card)

-- ---- 3. Done, reopen: the same number (this is what was reported: 67 on the card, 71 when it was reopened)
tapButton(card, "done")
check("Done closes the card", not onStack(card))
local layout_after_done = pair(conf.h_page_margins) .. "/" .. tostring(conf.font_size)
local card2 = openCard()
check("the reopened card shows the number the full card showed after Accept", card2.report.chars == accepted_chars and cardLines(card2) == accepted_lines,
    card2.report.chars .. " [" .. cardLines(card2) .. "] vs " .. accepted_chars .. " [" .. accepted_lines .. "]")
check("the layout was kept by Done", pair(conf.h_page_margins) .. "/" .. tostring(conf.font_size) == layout_after_done)

-- ---- 4. Cancel on the shrunk card puts everything back, and the card shows the start (also not one step behind)
tapButton(card2, "text_more")
tapButton(card2, "margins_more")
tapButton(card2, "cancel")
local truth_cancel, truth_cancel_lines = settled()
check("Cancel (shrunk): the layout is the one the card opened with", pair(conf.h_page_margins) .. "/" .. tostring(conf.font_size) == layout_after_done,
    pair(conf.h_page_margins) .. "/" .. tostring(conf.font_size) .. " vs " .. layout_after_done)
check("Cancel (shrunk): the full card is back and shows what the page holds",
    card2.compact == false and card2.report.chars == truth_cancel and cardLines(card2) == truth_cancel_lines,
    card2.report.chars .. " [" .. cardLines(card2) .. "] vs " .. truth_cancel .. " [" .. truth_cancel_lines .. "]")
check("Cancel (shrunk): and it is the number that was there when the card opened", card2.report.chars == accepted_chars)

-- ---- 5. Cancel on the full card after steps: back to the start of the popup, the card closes
tapButton(card2, "margins_less")
tapButton(card2, "accept")
tapButton(card2, "cancel")
check("Cancel (full) closes the card", not onStack(card2))
check("Cancel (full): everything is as it was when the popup opened", pair(conf.h_page_margins) .. "/" .. tostring(conf.font_size) == layout_after_done)
local truth_final = settled()
local card3 = openCard()
check("and reopening shows the page as it is", card3.report.chars == truth_final, card3.report.chars .. " vs " .. truth_final)

-- ---- 6. settling puts nothing on the screen: the reader's own paint runs a few times (not without end), into a buffer of
-- its own, and no repaint is forced or run (every one of those would be a refresh of the panel)
local paints, forced, repaints_run = 0, 0, 0
local seen_buffers, buffer_count = {}, 0
local real_paint, real_force, real_repaint = ui.view.paintTo, UIManager.forceRePaint, UIManager._repaint
ui.view.paintTo = function(self, bb, x, y)
    paints = paints + 1
    if not seen_buffers[bb] then seen_buffers[bb] = true; buffer_count = buffer_count + 1 end
    return real_paint(self, bb, x, y)
end
UIManager.forceRePaint = function(...) forced = forced + 1; return real_force(...) end
UIManager._repaint = function(...) repaints_run = repaints_run + 1; return real_repaint(...) end
plugin:onControl(card3, {}, "margins_more")
ui.view.paintTo, UIManager.forceRePaint, UIManager._repaint = real_paint, real_force, real_repaint
check("one change: the reader paints the page 1 to 3 times for the measurement", paints >= 1 and paints <= 3, paints)
check("all of them into one buffer", buffer_count == 1, buffer_count)
check("and that buffer is not the screen's", next(seen_buffers) ~= Screen.bb)
check("nothing was forced onto the screen, and no repaint ran", forced == 0 and repaints_run == 0, forced .. " forced, " .. repaints_run .. " run")
Screen:shot((os.getenv("SHOT_DIR") or ".") .. "/partial_1_after_steps.png")
UIManager:close(card3)
UIManager:forceRePaint()

if failures > 0 then print(failures .. " FAILURE(S)"); os.exit(1) end
print("all checks passed")
os.exit(0)
