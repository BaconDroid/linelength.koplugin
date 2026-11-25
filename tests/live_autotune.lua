-- Developer tool, not part of the plugin. Runs the auto-tune against a real book in a real KOReader:
-- the document engine (crengine), the layout changes, the measurement. Nothing is stubbed.
-- See tests/render.lua for how to get a KOReader build to run this with:
--   cd <koreader>/lib/koreader
--   HOME=<empty dir> PLUGIN_DIR=<this repo> BOOK=<file.epub> SDL_VIDEODRIVER=dummy \
--     EMULATE_READER_W=1264 EMULATE_READER_H=1680 EMULATE_READER_DPI=300 ./luajit <this repo>/tests/live_autotune.lua
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
local UIManager = require("ui/uimanager")
local Screen = Device.screen
local W, H = Screen:getWidth(), Screen:getHeight()
local book = os.getenv("BOOK")
assert(book, "set BOOK=<path to an epub>")

local function check(name, cond, detail)
    print(string.format("%s %s%s", cond and "ok  " or "FAIL", name, detail and (" (" .. detail .. ")") or ""))
    if not cond then os.exit(1) end
end

local refreshes = 0
local real_setDirty = UIManager.setDirty
UIManager.setDirty = function(...) refreshes = refreshes + 1; return real_setDirty(...) end
local real_forceRePaint = UIManager.forceRePaint
UIManager.forceRePaint = function(...) refreshes = refreshes + 1; return real_forceRePaint(...) end

package.path = os.getenv("PLUGIN_DIR") .. "/?.lua;" .. package.path
local LineLength = require("main")
local AutoTune = require("linelength/autotune")

local doc = require("document/documentregistry"):openDocument(book)
check("the book opens", doc ~= nil, book)
doc:setViewDimen(Screen:getSize())
doc:setFontFace("Noto Serif")

-- The layout the reader has now, and the one the plugin changes: as KOReader keeps them, in unscaled
-- units, in the document's own settings.
local layout = { h_page_margins = { 10, 10 }, font_size = 22 }
doc.configurable = layout
doc:setFontSize(Screen:scaleBySize(layout.font_size))
doc:setPageMargins(Screen:scaleBySize(layout.h_page_margins[1]), Screen:scaleBySize(10),
    Screen:scaleBySize(layout.h_page_margins[2]), Screen:scaleBySize(10))
doc:render()

local pages = doc:getPageCount()
check("the book has pages", pages > 20, pages .. " pages")
print(string.format("book: %s / %d pages / %dx%d px", book, pages, W, H))

local rect = require("ui/geometry"):new{ x = 0, y = 0, w = W, h = H }
local paints = 0
local ui = {
    document = doc,
    rolling = {},
    configurable = layout,
    view = { paintTo = function(_self, bb, x, y)
        paints = paints + 1
        doc:drawCurrentView(bb, x, y, rect)
    end },
}
-- The reader answers the events the plugin sends, as ReaderTypeset and ReaderFont do.
function ui:handleEvent(ev)
    if ev.handler == "onGotoPage" then
        doc:gotoPage(ev.args[1])
        return true
    end
    if ev.handler == "onConfigChange" then
        -- As ReaderCoptListener does: the value goes into the document's own settings.
        layout[ev.args[1]] = ev.args[2]
        return true
    end
    if ev.handler == "onSetPageHorizMargins" then
        -- As ReaderTypeset does: the horizontal margins change, the vertical ones stay, and the
        -- configurable keeps them so that KOReader saves them with the book.
        layout.h_page_margins = { ev.args[1][1], ev.args[1][2] }
        doc:setPageMargins(Screen:scaleBySize(ev.args[1][1]), Screen:scaleBySize(10),
            Screen:scaleBySize(ev.args[1][2]), Screen:scaleBySize(10))
        doc:render()
        return true
    end
    if ev.handler == "onSetFontSize" then
        layout.font_size = ev.args[1]
        doc:setFontSize(Screen:scaleBySize(ev.args[1]))
        doc:render()
        return true
    end
end

-- The settings of the book: the harness has no KOReader sidecar, so a plain table stands in for it.
local book_store = {}
local book_store = {}
ui.doc_settings = {
    readSetting = function(_self, key) return book_store[key] end,
    saveSetting = function(_self, key, value) book_store[key] = value end,
    delSetting = function(_self, key) book_store[key] = nil end,
    flush = function() end,
}

local plugin = LineLength:new{ document = doc, ui = ui }
plugin:init()

-- The settings the plugin reads: the harness has no KOReader settings file, so they are given here.
local Settings = require("linelength/settings")
local real_read = Settings.read
Settings.read = function() return {
    enabled = true, tune_once = true,
    band_min = 56, band_max = 60, target = 58,
    margin_min = 20, margin_max = 50, max_chars_per_step = 6,
    sample_first = 0, sample_middle = 6, sample_last = 0, max_steps = 6,
} end

local settings = {
    enabled = true,
    band_min = 56, band_max = 60, target = 58,
    margin_min = 20, margin_max = 50,
    max_chars_per_step = 6,
    sample_first = 0, sample_middle = 6, sample_last = 0,
    max_steps = 6,
}

-- The book starts badly set up: a big text on wide margins makes the lines too short.
layout.font_size = tonumber(os.getenv("FONT")) or 22
if os.getenv("START") == "long" then
    -- A small text on narrow margins makes the lines too long.
    layout.h_page_margins = { 0, 0 }
    layout.font_size = tonumber(os.getenv("FONT")) or 16
else
    -- Wide margins make the lines too short.
    layout.h_page_margins = { 60, 60 }
end
local start_font = layout.font_size
local start_margin = layout.h_page_margins[1]
doc:setPageMargins(Screen:scaleBySize(layout.h_page_margins[1]), Screen:scaleBySize(10),
    Screen:scaleBySize(layout.h_page_margins[2]), Screen:scaleBySize(10))
doc:setFontSize(Screen:scaleBySize(layout.font_size))
doc:render()

local start_page = math.floor(pages / 2)
doc:gotoPage(start_page)
doc:render()

local before = plugin:measureSample()
check("the book is measured before the tune", before ~= nil)
print(string.format("before: median %s (min %s, max %s)", tostring(before.median), tostring(before.min), tostring(before.max)))
-- The book has to start outside the band for the tune to have anything to do. The margins are set
-- wide or narrow to get there; at some text sizes the band is reached either way, and then the tune
-- has nothing to do, which is a result in itself.
local starts_outside = not AutoTune.inBand(before.median)
if starts_outside then
    if before.median > settings.band_max then
        check("the lines are too long to begin with", true, before.median .. " characters")
    else
        check("the lines are too short to begin with", true, before.median .. " characters")
    end
else
    print(string.format("the book starts in the band already (%d characters): the tune has nothing to do",
        before.median))
end

-- The place the reader is at in the text, before the tune: the layout changes and the book is laid
-- out again, so the page numbers move, and the reader has to stay on the same place in the text.
-- The place in the text is the xpointer: it points at a spot in the text itself, and the text it
-- points at is still there after the change of the layout.
local anchor = doc:getXPointer()
check("the reader has an anchor in the text", anchor ~= nil, tostring(anchor))

refreshes, paints = 0, 0
local clock = os.clock()
local result = plugin:autoTune(settings)
local elapsed = os.clock() - clock
check("the auto-tune ran", result ~= nil)
print(string.format("auto-tune: %d steps, %s characters, %.2f s of CPU, %d pages drawn",
    result.steps, tostring(result.chars), elapsed, paints))
print(string.format("layout now: margins %d/%d, text size %d", layout.h_page_margins[1],
    layout.h_page_margins[2], layout.font_size))

-- The layout changes when there is something to change, and stays as it is when the margins are
-- already at the bound the reader set and the lines cannot be any shorter.
local margins_moved = layout.h_page_margins[1] ~= start_margin
check("the auto-tune changed the layout when it could", result.changed == margins_moved,
    tostring(result.changed) .. ", margins moved: " .. tostring(margins_moved))
-- The tune ends in the band, unless the margins cannot get there: a text too small for the band
-- cannot be shortened by the margins alone, and the tune stops at the bound.
if AutoTune.inBand(result.chars) then
    check("the line length is now in the band", true, tostring(result.chars))
else
    check("the tune went as far as the margins go", layout.h_page_margins[1] == settings.margin_max
        or layout.h_page_margins[1] == settings.margin_min, tostring(layout.h_page_margins[1]))
end
check("the margins stayed inside the bounds", layout.h_page_margins[1] >= settings.margin_min
    and layout.h_page_margins[1] <= settings.margin_max, tostring(layout.h_page_margins[1]))
check("it took a few steps", result.steps <= settings.max_steps, result.steps .. " steps")
-- The margins move towards the target: wider when the lines are too long, narrower when they are
-- too short. The text size never moves.
if starts_outside and margins_moved then
    -- The margins move towards the target: wider when the lines are too long, narrower when they are
    -- too short, unless they are already at the bound that movement would need.
    if before.median > settings.band_max then
        check("the margins went out", layout.h_page_margins[1] > start_margin
            or layout.h_page_margins[1] == settings.margin_max, tostring(layout.h_page_margins[1]))
    else
        check("the margins came in", layout.h_page_margins[1] < start_margin
            or layout.h_page_margins[1] == settings.margin_min, tostring(layout.h_page_margins[1]))
    end
end
check("the margins are even", layout.h_page_margins[1] == layout.h_page_margins[2])
check("the text size was never touched", layout.font_size == start_font,
    tostring(layout.font_size) .. " instead of " .. tostring(start_font))
check("the margins are inside their bounds", layout.h_page_margins[1] >= settings.margin_min
    and layout.h_page_margins[1] <= settings.margin_max, tostring(layout.h_page_margins[1]))

local after = plugin:measureSample()
check("the book measures the same afterwards", after ~= nil and after.median == result.chars,
    tostring(after and after.median) .. " vs " .. tostring(result.chars))
check("the text size is still the one the reader chose", layout.font_size == start_font,
    tostring(layout.font_size))
-- The layout changed, so the book is laid out again and the page numbers move: the reader stays on
-- the same place in the text, not on the same page number.
check("the reader is still in the book", doc:getCurrentPage() >= 1 and doc:getCurrentPage() <= doc:getPageCount(),
    "page " .. doc:getCurrentPage() .. " of " .. doc:getPageCount())
-- The anchor is the place in the text the reader was at: after the change of the layout it can be on
-- another page, but it is the same text, and the reader is still on it.
local anchor_page = doc:getPageFromXPointer(anchor)
check("the anchor is still in the book", anchor_page ~= nil and anchor_page >= 1
    and anchor_page <= doc:getPageCount(), "page " .. tostring(anchor_page))
check("the reader is still on the same place in the text", doc:isXPointerInCurrentPage(anchor),
    "the anchor is on page " .. tostring(anchor_page) .. ", the reader is on page " .. doc:getCurrentPage())
print(string.format("the book is now %d pages (it was %d), the reader is on page %d",
    doc:getPageCount(), pages, doc:getCurrentPage()))

local again = plugin:autoTune(settings)
check("a second run leaves the book alone", again and again.changed == false, tostring(again and again.changed))
check("and it measures the same", again and again.chars == result.chars, tostring(again and again.chars))

-- The flag: a book that was already tuned is not measured again when it is opened.
local BookState = require("linelength/bookstate")
BookState.markTuned(ui)
check("the book is remembered as tuned", BookState.wasTuned(ui) == true, "the flag is in the settings of the book")
local measured_again = false
plugin.measureSample = function() measured_again = true; return nil, "unsupported" end
plugin:onReaderReady()
check("a tuned book is not measured again", measured_again == false, "measured_again=" .. tostring(measured_again))

-- With the flag off, it is measured again.
BookState.clearTuned(ui)
measured_again = false
plugin:onReaderReady()
check("a book that was not tuned is measured again", measured_again == true, "measured_again=" .. tostring(measured_again))

print("ALL LIVE CHECKS PASSED")
os.exit(0)
