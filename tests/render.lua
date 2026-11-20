-- Developer tool, not part of the plugin. Renders the button dialog and the details card with the
-- real KOReader widget code (a macOS KOReader build run headless) and saves PNGs at Libra Colour size.
--   cd <KOReader.app>/Contents/koreader
--   HOME=<empty dir> PLUGIN_DIR=<this repo> SHOT_DIR=<out dir> SDL_VIDEODRIVER=dummy \
--     EMULATE_READER_W=1264 EMULATE_READER_H=1680 EMULATE_READER_DPI=300 ./luajit <this repo>/tests/render.lua
-- It shows what the code draws into KOReader's buffer, not what the Kaleido panel displays.
io.stdout:setvbuf("line")
os.setlocale("C", "numeric")
require("setupkoenv")
G_defaults = require("luadefaults"):open()
local DataStorage = require("datastorage")
G_reader_settings = require("luasettings"):open(DataStorage:getDataDir() .. "/settings.reader.lua")
local Device = require("device")
local CanvasContext = require("document/canvascontext")
CanvasContext:init(Device)
require("ui/bidi").setup(nil)
-- what reader.lua does at startup: use the C blitter (the one that runs on the device)
local _bb = require("ffi/blitbuffer")
_bb:setUseCBB(true)
print("C blitter enabled:", _bb:enableCBB(true))

local Blitbuffer = require("ffi/blitbuffer")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local TextBoxWidget = require("ui/widget/textboxwidget")
local ButtonDialog = require("ui/widget/buttondialog")
local UIManager = require("ui/uimanager")
local Screen = Device.screen

package.path = (os.getenv("PLUGIN_DIR") or ".") .. "/?.lua;" .. package.path
local Report = require("wcount/report")
local Details = require("wcount/details")

local OUT = os.getenv("SHOT_DIR") or "."
print(string.format("screen %dx%d dpi %d colour screen=%s colour enabled=%s", Screen:getWidth(), Screen:getHeight(),
    Screen:getDPI(), tostring(Device:hasColorScreen()), tostring(Screen:isColorEnabled())))

local LABELS = { too_long = "Too long", still_readable = "Still readable", comfortable = "Comfortable",
    excellent = "Excellent", short = "Short" }

local lorem = "It was a bright cold day in April, and the clocks were striking thirteen. Winston Smith, "
    .. "his chin nuzzled into his breast in an effort to escape the vile wind, slipped quickly through the "
    .. "glass doors of Victory Mansions, though not quickly enough to prevent a swirl of gritty dust from "
    .. "entering along with him. The hallway smelt of boiled cabbage and old rag mats. At one end of it a "
    .. "coloured poster, too large for indoor display, had been tacked to the wall. "
local page = FrameContainer:new{
    background = Blitbuffer.COLOR_WHITE,
    bordersize = 0,
    padding = Screen:scaleBySize(46),
    TextBoxWidget:new{
        text = lorem .. lorem .. lorem .. lorem,
        face = Font:getFace("cfont", 26),
        width = Screen:getWidth() - 2 * Screen:scaleBySize(46),
    },
}
UIManager:show(page)
UIManager:forceRePaint()

local function snap(name, widget)
    UIManager:show(widget)
    UIManager:forceRePaint()
    Screen:shot(OUT .. "/" .. name .. ".png")
    print("saved " .. name)
    UIManager:close(widget)
    UIManager:forceRePaint()
end

local function card(chars, use_color, name)
    local counts = { chars = chars, chars_no_spaces = chars - math.floor(chars / 6), words = math.floor(chars / 6) }
    snap(name, Details:new{ report = Report.build(counts, LABELS), use_color = use_color })
end

card(58, true, "card_excellent_colour")
card(70, true, "card_comfortable_colour")
card(78, true, "card_still_readable_colour")
card(88, true, "card_too_long_colour")
card(30, true, "card_short_colour")
card(58, false, "card_excellent_nocolour")

-- the highlight dialog with our single plain button, as a user would see it
local function btn(text) return { text = text, callback = function() end } end
snap("dialog_with_button", ButtonDialog:new{
    buttons = {
        { btn("Select"), btn("Highlight") },
        { btn("Copy"), btn("Add note") },
        { btn("Wikipedia"), btn("Dictionary") },
        { btn("Translate"), btn("View HTML") },
        { btn("Generate QR code"), btn("Search") },
        { btn("Line: 58 chars · Excellent") },
    },
})
print("done")
os.exit(0)
