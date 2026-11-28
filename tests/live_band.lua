-- Developer tool, not part of the plugin. For a given text size, it reports the margins that put the
-- line length in a given band, so the bounds of the auto-tune can be set from measurements.
--   cd <koreader>/lib/koreader
--   HOME=<empty dir> PLUGIN_DIR=<this repo> BOOK=<file.epub> SDL_VIDEODRIVER=dummy \
--     EMULATE_READER_W=1264 EMULATE_READER_H=1680 EMULATE_READER_DPI=300 ./luajit <this repo>/tests/live_band.lua
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
local band_min = tonumber(os.getenv("BAND_MIN")) or 56
local band_max = tonumber(os.getenv("BAND_MAX")) or 60

package.path = os.getenv("PLUGIN_DIR") .. "/?.lua;" .. package.path
local PageLines = require("linelength/pagelines")
local util = require("util")

local doc = require("document/documentregistry"):openDocument(book)
doc:setViewDimen(Screen:getSize())
doc:setFontFace("Noto Serif")

local rect = require("ui/geometry"):new{ x = 0, y = 0, w = W, h = H }
local Blitbuffer = require("ffi/blitbuffer")
local buffer = Blitbuffer.new(W, H, Screen.bb and Screen.bb:getType())

local function longest_line()
    doc:drawCurrentView(buffer, 0, 0, rect)
    local lines = PageLines.collect(doc, W, H, util.cleanupSelectedText)
    local longest = 0
    for _i, line in ipairs(lines) do
        if line.chars > longest then longest = line.chars end
    end
    return longest
end

print(string.format("band %d-%d characters, screen %dx%d", band_min, band_max, W, H))
for _f, font in ipairs({ 18, 20, 22 }) do
    doc:setFontSize(Screen:scaleBySize(font))
    local hits, first, last, at_target = {}, nil, nil, nil
    for margin = 5, 65, 5 do
        doc:setPageMargins(Screen:scaleBySize(margin), Screen:scaleBySize(10),
            Screen:scaleBySize(margin), Screen:scaleBySize(10))
        doc:render()
        doc:gotoPage(10)
        local chars = longest_line()
        if chars >= band_min and chars <= band_max then
            hits[#hits + 1] = string.format("%d:%d", margin, chars)
            first = first or margin
            last = margin
            for _t, target in ipairs({ 56, 57, 58, 59, 60 }) do
                if chars == target then
                    at_target = at_target or {}
                    at_target[target] = at_target[target] or margin
                end
            end
        end
    end
    local per_target = {}
    for _t, margin in pairs(at_target or {}) do per_target[#per_target + 1] = _t .. "->" .. margin end
    table.sort(per_target)
    print(string.format("font %2d : de %s a %s  [%s]",
        font, tostring(first), tostring(last), table.concat(per_target, " ")))
end
os.exit(0)
