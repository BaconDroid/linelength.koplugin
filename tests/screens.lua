-- Geometry of the cards on the screen this test runs on (set EMULATE_READER_W / _H / _DPI, any size, either orientation):
-- every card has to fit on the screen, with room around it, and sit in the middle; in landscape it has to be wider than
-- tall; and when it shrinks, the buttons have to stay where they were. Run with a desktop build of KOReader:
--   cd <KOReader.app>/Contents/koreader
--   HOME=<empty dir> PLUGIN_DIR=<this repo> SDL_VIDEODRIVER=dummy EMULATE_READER_W=1680 EMULATE_READER_H=1264 \
--     EMULATE_READER_DPI=300 ./luajit <this repo>/tests/screens.lua
-- It shows what the code lays out in KOReader's buffer, not what the Kaleido panel displays.
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

local UIManager = require("ui/uimanager")
local Screen = Device.screen
package.path = (os.getenv("PLUGIN_DIR") or ".") .. "/?.lua;" .. package.path
local Report = require("linelength/report")
local Details = require("linelength/details")

local W, H = Screen:getWidth(), Screen:getHeight()
local landscape = W > H
print(string.format("screen %dx%d dpi %d (%s)", W, H, Screen:getDPI(), landscape and "landscape" or "portrait"))

local failures, passes = 0, 0
local function check(name, ok, detail)
    if ok then
        passes = passes + 1
    else
        failures = failures + 1
        print(string.format("FAIL  %s%s", name, detail ~= nil and ("  (" .. tostring(detail) .. ")") or ""))
    end
end

local LABELS = { too_long = "Too long", still_readable = "Still readable", comfortable = "Comfortable", excellent = "Excellent", short = "Short" }
local function ln(chars, text, number) return { chars = chars, chars_no_spaces = chars, words = 1, text = text, number = number } end
local PAGE = {
    ln(70, "mountain the two go other and his valley like carefully silence", 5),
    ln(66, "time shadow from its stranger quiet valley only mountain", 12),
    ln(64, "carefully us so then shadow said then considerably as ancient", 23),
}
local WIDE = { ln(88, string.rep("W", 60), 1), ln(80, string.rep("M", 60), 10), ln(75, "déjà vu, naïve café – “quoted” text with accents and punctuation", 24) }
local ALL = { margins_less = true, margins_more = true, text_less = true, text_more = true }
local VALUES = { margins = "10", size = "22" }

local function dimenOf(w) local d = w.dimen; return d and { x = d.x, y = d.y, w = d.w, h = d.h } end
local function inside(inner, outer, slack)
    slack = slack or 0
    return inner.x >= outer.x - slack and inner.y >= outer.y - slack and inner.x + inner.w <= outer.x + outer.w + slack and inner.y + inner.h <= outer.y + outer.h + slack
end
local IDS = { "margins_less", "margins_more", "text_less", "text_more", "cancel", "done", "accept" }
local function places(card)
    local out = {}
    for _i, id in ipairs(IDS) do
        local b = card.buttons and card.buttons[id]
        if b and b.dimen then out[#out + 1] = string.format("%s=%d,%d,%d,%d", id == "accept" and "done" or id, b.dimen.x, b.dimen.y, b.dimen.w, b.dimen.h) end
    end
    return table.concat(out, " ")
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
    for _i, t in ipairs(texts(card)) do if t == wanted then return true end end
    return false
end
-- the air between the Text size stepper and the buttons under it
local function airAboveButtons(card)
    local above, below = card.buttons.text_more.dimen, card.buttons.cancel.dimen
    return below.y - (above.y + above.h)
end

-- the room that has to be left around a card: a twentieth of the screen's shorter side, at least
local ROOM = math.floor(math.min(W, H) / 40)

local function show(card)
    UIManager:show(card)
    UIManager:forceRePaint()
    return card
end
local function close(card)
    UIManager:close(card)
    UIManager:forceRePaint()
end

-- what every card must satisfy on this screen
local function fits(name, card, full)
    local frame = dimenOf(card.frame)
    check(name .. ": the card has a place on the screen", frame ~= nil)
    if not frame then return end
    local d = string.format("card %dx%d at (%d,%d) on %dx%d", frame.w, frame.h, frame.x, frame.y, W, H)
    check(name .. ": it fits on the screen", inside(frame, { x = 0, y = 0, w = W, h = H }), d)
    check(name .. ": with room above and below", frame.y >= ROOM and H - (frame.y + frame.h) >= ROOM, d .. ", room " .. ROOM)
    check(name .. ": and at the sides", frame.x >= ROOM and W - (frame.x + frame.w) >= ROOM, d)
    for id, b in pairs(card.buttons or {}) do
        local bd = dimenOf(b)
        check(name .. ": button " .. id .. " is inside the card", bd ~= nil and inside(bd, frame, 1), bd and string.format("%d,%d,%d,%d", bd.x, bd.y, bd.w, bd.h))
    end
    local want_width = math.floor(W * (landscape and 0.9 or 0.8))
    check(name .. ": it takes " .. (landscape and "90" or "80") .. "% of the width of the screen", math.abs(frame.w - want_width) <= 1, d .. ", want " .. want_width)
    if card.buttons and card.buttons.text_more then
        local confirm = card.buttons.done or card.buttons.accept
        local stepper_edge = card.buttons.text_more.dimen.x + card.buttons.text_more.dimen.w
        local confirm_edge = confirm.dimen.x + confirm.dimen.w
        check(name .. ": the steppers end where the buttons under them end", math.abs(stepper_edge - confirm_edge) <= 2, stepper_edge .. " vs " .. confirm_edge)
        check(name .. ": there is air between the Text size stepper and the buttons", airAboveButtons(card) >= Screen:scaleBySize(12), airAboveButtons(card))
    end
    if full then
        check(name .. ": it is centred across", math.abs(frame.x - (W - (frame.x + frame.w))) <= 2, d)
        check(name .. ": and centred down", math.abs(frame.y - (H - (frame.y + frame.h))) <= 2, d)
        if landscape then
            check(name .. ": wider than tall (landscape)", frame.w > frame.h, d)
        end
    end
end

-- a card the way the plugin uses it: full first, then shrunk by an update after a tap on a stepper
local function shrink(card)
    card.shrink_on_update = true
    card:update(card.report)
    card.shrink_on_update = false
    UIManager:forceRePaint()
end

local function wantTexts(name, card, present, absent)
    for _i, t in ipairs(present or {}) do
        check(name .. ": it shows \"" .. t .. "\"", hasText(card, t))
    end
    for _i, t in ipairs(absent or {}) do
        check(name .. ": it does not show \"" .. t .. "\"", not hasText(card, t))
    end
end

-- what is on each card (nothing may go missing from a column): `full` for the full card, `small` for the shrunk one
local function cardCase(name, top, controls, report, full_texts, small_texts, small_absent)
    local card = show(Details:new{ report = report or Report.buildPage(top, LABELS), use_color = true, controls = controls, values = controls and VALUES or nil })
    fits(name .. " (full)", card, true)
    wantTexts(name .. " (full)", card, full_texts)
    if landscape and not controls then
        -- two columns: the score on the left, centred against the other column by a spacer above and one below it
        local columns = card.frame[1] and card.frame[1][3]
        local left = columns and columns[1]
        local above, below = left and left[1], left and left[#left]
        check(name .. " (full): the score is centred against the other column",
            above ~= nil and below ~= nil and (above.width or 0) > 0 and math.abs((above.width or 0) - (below.width or -99)) <= 1,
            above and below and (tostring(above.width) .. " above, " .. tostring(below.width) .. " below") or "no columns")
    end
    if landscape and controls then
        -- the spare height of the right column goes between the longest lines and the steppers, so that the lines start at
        -- the top, level with the score, and the steppers stay at the bottom
        local columns = card.frame[1] and card.frame[1][3]
        local right = columns and columns[3]
        check(name .. " (full): the longest lines start at the top of the right column (no spacer above them)", right ~= nil and right[1] ~= nil and right[1].dimen ~= nil)
    end
    local full_places = places(card)
    local full_air = controls and airAboveButtons(card)
    if controls then
        shrink(card)
        check(name .. " (shrunk): it is shrunk", card.compact == true)
        fits(name .. " (shrunk)", card, false)
        wantTexts(name .. " (shrunk)", card, small_texts, small_absent)
        check(name .. " (shrunk): the same air above the buttons as on the full card", airAboveButtons(card) == full_air, airAboveButtons(card) .. " vs " .. tostring(full_air))
        check(name .. " (shrunk): the buttons are where they were on the full card", places(card) == full_places, places(card) .. " | " .. full_places)
        local small = dimenOf(card.frame)
        check(name .. " (shrunk): it is smaller than the full card", small.h < (UIManager and (card.anchor_bottom or H)) , small.h)
        -- and back: the buttons are in the same places again
        card.expand_on_update = true
        card:update(card.report)
        card.expand_on_update = false
        UIManager:forceRePaint()
        check(name .. " (full again): the buttons are where they were", places(card) == full_places, places(card) .. " | " .. full_places)
        fits(name .. " (full again)", card, true)
    end
    close(card)
end

local BANDS_COMFORTABLE = { "○ Excellent", "● Comfortable", "○ Still readable", "○ Too long" }
local function with(list, more)
    local out = {}
    for _i, t in ipairs(list) do out[#out + 1] = t end
    for _i, t in ipairs(more) do out[#out + 1] = t end
    return out
end
local SELECTION = { "58", "characters", "Excellent", "With spaces", "Without spaces", "Words", "● Excellent", "○ Comfortable", "○ Still readable", "○ Too long" }
local PAGE_TEXTS = with(BANDS_COMFORTABLE, { "70", "Comfortable", "characters in the longest line", "Longest lines on this page:", "L5:", "L12:", "L23:" })
local CONTROL_TEXTS = with(PAGE_TEXTS, { "Margins", "Text size", "10", "22", "Cancel", "Done" })
local SMALL_TEXTS = { "70", "Comfortable", "characters in the longest line", "Margins", "Text size", "10", "22", "Cancel", "Accept" }
local SMALL_ABSENT = { "Longest lines on this page:", "● Comfortable", "○ Excellent", "Done" }

cardCase("selection card", nil, nil, Report.build({ chars = 58, chars_no_spaces = 49, words = 9 }, LABELS), SELECTION)
cardCase("page card", PAGE, nil, nil, PAGE_TEXTS)
cardCase("page card with controls", PAGE, ALL, nil, CONTROL_TEXTS, SMALL_TEXTS, SMALL_ABSENT)
cardCase("page card with controls, the widest letters", WIDE, ALL, nil, { "88", "Too long", "Margins", "Text size", "L1:", "L10:", "L24:", "Cancel", "Done" },
    { "88", "Too long", "Margins", "Text size", "Cancel", "Accept" }, { "Longest lines on this page:", "Done" })
cardCase("page card with controls, one line", { ln(60, "only one line has text on this page at all", 3) }, ALL, nil,
    { "60", "Longest line on this page:", "L3:", "Margins", "Text size", "Cancel", "Done" }, { "60", "Margins", "Text size", "Cancel", "Accept" }, { "Longest line on this page:", "Done" })

print(string.format("%d checks passed, %d failed", passes, failures))
if failures > 0 then
    print(failures .. " FAILURE(S)")
    os.exit(1)
end
print("all checks passed")
os.exit(0)
