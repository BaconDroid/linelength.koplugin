-- Developer tool, not part of the plugin. Measures what the top and bottom margins do to the line
-- length: they change how many lines fit on a page, not how many characters a line holds.
--   cd <koreader>/lib/koreader
--   HOME=<empty dir> PLUGIN_DIR=<this repo> BOOK=<file.epub> SDL_VIDEODRIVER=dummy \
--     EMULATE_READER_W=1264 EMULATE_READER_H=1680 EMULATE_READER_DPI=300 ./luajit <this repo>/tests/live_margins.lua
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
doc:setFontSize(Screen:scaleBySize(22))

local rect = require("ui/geometry"):new{ x = 0, y = 0, w = W, h = H }
local Blitbuffer = require("ffi/blitbuffer")
local buffer = Blitbuffer.new(W, H, Screen.bb and Screen.bb:getType())

local function longest_line()
    doc:drawCurrentView(buffer, 0, 0, rect)
    local lines = PageLines.collect(doc, W, H, util.cleanupSelectedText)
    local longest, count = 0, #lines
    for _i, line in ipairs(lines) do
        if line.chars > longest then longest = line.chars end
    end
    return longest, count
end

print(string.format("%6s %6s %6s   %8s %8s", "h", "top", "bottom", "chars", "lines"))
for _i, h in ipairs({ 10, 30 }) do
    for _j, v in ipairs({ 0, 10, 30, 60 }) do
        doc:setPageMargins(Screen:scaleBySize(h), Screen:scaleBySize(v),
            Screen:scaleBySize(h), Screen:scaleBySize(v))
        doc:render()
        doc:gotoPage(10)
        local chars, lines = longest_line()
        print(string.format("%6d %6d %6d   %8d %8d", h, v, v, chars, lines))
    end
end
os.exit(0)
