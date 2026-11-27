-- Developer tool, not part of the plugin. Measures what a line of text holds on a screen of a given
-- size: how many characters fit on a line, for a given text size and margins. It is what the
-- auto-tune works with, and it depends on the screen, not only on the book.
--   cd <koreader>/lib/koreader
--   HOME=<empty dir> PLUGIN_DIR=<this repo> BOOK=<file.epub> SDL_VIDEODRIVER=dummy \
--     EMULATE_READER_W=1264 EMULATE_READER_H=1680 EMULATE_READER_DPI=300 ./luajit <this repo>/tests/live_screens.lua
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
local Screen = Device.screen
local W, H = Screen:getWidth(), Screen:getHeight()
local book = os.getenv("BOOK")
assert(book, "set BOOK=<path to an epub>")

package.path = os.getenv("PLUGIN_DIR") .. "/?.lua;" .. package.path
local PageLines = require("linelength/pagelines")
local util = require("util")

local doc = require("document/documentregistry"):openDocument(book)
doc:setViewDimen(Screen:getSize())
doc:setFontFace("Noto Serif")
doc:render()

local rect = require("ui/geometry"):new{ x = 0, y = 0, w = W, h = H }
local Blitbuffer = require("ffi/blitbuffer")
local buffer = Blitbuffer.new(W, H, Screen.bb and Screen.bb:getType())
local function draw()
    doc:drawCurrentView(buffer, 0, 0, rect)
end

local function longest_line()
    local lines = PageLines.collect(doc, W, H, util.cleanupSelectedText)
    local longest = 0
    for _i, line in ipairs(lines) do
        if line.chars > longest then longest = line.chars end
    end
    return longest
end

print(string.format("screen %d x %d px, dpi %d -> %d x %d KOReader units",
    W, H, Screen:getDPI(), Screen:getWidth(), Screen:getHeight()))
print(string.format("%8s %8s %8s   %s", "font", "margin", "chars", "note"))
for _i, font in ipairs({ 14, 16, 18, 20, 22, 24, 26 }) do
    for _j, margin in ipairs({ 0, 10, 20, 30, 40, 60 }) do
        doc:setFontSize(Screen:scaleBySize(font))
        doc:setPageMargins(Screen:scaleBySize(margin), Screen:scaleBySize(10),
            Screen:scaleBySize(margin), Screen:scaleBySize(10))
        doc:render()
        doc:gotoPage(10)
        draw()
        local chars = longest_line()
        local band = ""
        if chars >= 50 and chars <= 66 then band = "in the band" end
        print(string.format("%8d %8d %8d   %s", font, margin, chars, band))
    end
end
os.exit(0)
