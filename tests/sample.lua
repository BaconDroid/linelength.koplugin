-- Developer tool, not part of the plugin. Runs the page sample against a real book with KOReader's real
-- crengine. Nothing is stubbed: the document engine, the page arithmetic and the sample walk are the ones
-- that run on a device. See tests/render.lua for how to get a KOReader build to run this with:
--   cd <koreader>/lib/koreader
--   HOME=<empty dir> PLUGIN_DIR=<this repo> BOOK=<file.epub> SDL_VIDEODRIVER=dummy \
--     EMULATE_READER_W=1264 EMULATE_READER_H=1680 EMULATE_READER_DPI=300 ./luajit <this repo>/tests/sample.lua
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

-- Instrumented to prove the walk refreshes nothing and shows nothing.
local refreshes, shown = 0, {}
local real_setDirty = UIManager.setDirty
UIManager.setDirty = function(...) refreshes = refreshes + 1; return real_setDirty(...) end
local real_forceRePaint = UIManager.forceRePaint
UIManager.forceRePaint = function(...) refreshes = refreshes + 1; return real_forceRePaint(...) end
local real_show = UIManager.show
UIManager.show = function(_self, widget) shown[#shown + 1] = widget; return real_show(_self, widget) end

local function check(name, cond, detail)
    print(string.format("%s %s%s", cond and "ok  " or "FAIL", name, detail and (" (" .. detail .. ")") or ""))
    if not cond then os.exit(1) end
end

package.path = os.getenv("PLUGIN_DIR") .. "/?.lua;" .. package.path
local LineLength = require("main")

local doc = require("document/documentregistry"):openDocument(book)
check("the book opens", doc ~= nil, book)
doc:setViewDimen(Screen:getSize())
doc:setFontFace("Noto Serif")
doc:setFontSize(Screen:scaleBySize(22))
doc:setPageMargins(Screen:scaleBySize(10), Screen:scaleBySize(10), Screen:scaleBySize(10), Screen:scaleBySize(10))
doc:render()

local pages = doc:getPageCount()
check("the book has pages", pages > 20, pages .. " pages")
print(string.format("book: %s / %d pages / %dx%d px / font 22 / margins 10", book, pages, W, H))

-- A reader that answers GotoPage the way ReaderRolling does. The view is the real one a reader would have:
-- drawing the page goes through crengine's own rendering.
local rect = require("ui/geometry"):new{ x = 0, y = 0, w = W, h = H }
local paints = 0
local ui = {
    document = doc,
    rolling = {},
    view = { paintTo = function(_self, bb, x, y)
        paints = paints + 1
        doc:drawCurrentView(bb, x, y, rect)
    end },
}
function ui:handleEvent(ev)
    if ev.handler == "onGotoPage" then
        doc:gotoPage(ev.args[1])
        return true
    end
end

local plugin = LineLength:new{ document = doc, ui = ui }
plugin:init()

local start_page = math.floor(pages / 2)
ui:handleEvent(Event:new("GotoPage", start_page))
check("the reader is where it was put", doc:getCurrentPage() == start_page, "page " .. doc:getCurrentPage())

local clock = os.clock()
refreshes = 0
local sample, reason = plugin:measureSample()
local elapsed = os.clock() - clock
check("the sample is measured", sample ~= nil, reason)
check("the walk refreshed nothing on the e-ink panel", refreshes == 0, refreshes .. " refreshes")
print(string.format("sample: %d pages read of %d, %.2f s of CPU, %d pages drawn", #sample.values,
    sample.total, elapsed, paints))
print(string.format("median %s / shortest %s / longest %s", tostring(sample.median),
    tostring(sample.min), tostring(sample.max)))
print("pages: " .. (function()
    local t = {}
    for _i, p in ipairs(sample.pages) do t[#t + 1] = p.page .. ":" .. p.chars end
    return table.concat(t, " ")
end)())

check("the reader is back on its page", doc:getCurrentPage() == start_page, "page " .. doc:getCurrentPage())
check("one entry per page read", #sample.pages == #sample.values)
check("the counts are line lengths", sample.min >= 10 and sample.max <= 250,
    sample.min .. " to " .. sample.max)
check("the median sits between the extremes", sample.median >= sample.min and sample.median <= sample.max)

local before = plugin:measureSettled()
local after = plugin:measureSettled()
check("the page on screen still measures the same", before and after and before.chars == after.chars,
    tostring(before and before.chars) .. " then " .. tostring(after and after.chars))
check("and the reader did not move", doc:getCurrentPage() == start_page)

local second = plugin:measureSample()
check("a second sample gives the same median", second and second.median == sample.median,
    tostring(second and second.median) .. " vs " .. tostring(sample.median))
check("the reader is back on its page again", doc:getCurrentPage() == start_page)

print("--- what the reader is shown ---")
shown = {}
refreshes = 0
-- showSample shows the "measuring" message and waits for the next UI tick before the walk, so the
-- measurement has to be triggered the way the UI loop would do it.
-- UIManager:tickAfterNext wraps the action before queueing it, so the wrapper is what comes back.
local pending = UIManager.tickAfterNext
UIManager.tickAfterNext = function(_self, action, ...)
    pending(_self, action, ...)
    action(...)
    return function() end
end
plugin:showSample()
-- the first widget is the "measuring" message, the last one is the result
local message = shown[#shown]
for _i, widget in ipairs(shown) do
    if type(widget.text) == "string" and widget.text:find("Median line") then message = widget end
end
check("the message is shown", message ~= nil, tostring(#shown) .. " widgets")
-- Showing a message paints it: what must not refresh is the page walk inside the sample.
check("the measuring message, then the result", #shown == 2, tostring(#shown) .. " widgets")
if message and message.text then
    print(message.text)
end
check("the message names the median line length",
    message and message.text and message.text:find("Median line: " .. sample.median .. " chars") ~= nil,
    message and message.text or "no text")
check("the message says how many pages were read",
    message and message.text and message.text:find(#sample.values .. " of " .. pages) ~= nil,
    message and message.text or "no text")
print("ALL LIVE CHECKS PASSED")
os.exit(0)
