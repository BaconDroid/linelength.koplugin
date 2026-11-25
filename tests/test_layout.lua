package.path = "./?.lua;" .. package.path
local Layout = require("linelength/layout")

local failures = 0
local function expect(name, got, want)
    if got ~= want then
        failures = failures + 1
        print(string.format("FAIL %s: got %q, want %q", name, tostring(got), tostring(want)))
    end
end
local function pair(t)
    return t and (t[1] .. "," .. t[2]) or "nil"
end

expect("the step is 5% of the text width", Layout.STEP, 0.05)
expect("margins go from 0", Layout.MARGIN_MIN, 0)
expect("margins go to 140 (KOReader's own limit)", Layout.MARGIN_MAX, 140)
expect("font size goes from 12", Layout.FONT_MIN, 12)
expect("font size goes to 255", Layout.FONT_MAX, 255)

-- ---- margins, on a screen 560 wide. Each side moves by 2.5% of the text width: round(0.025 * text), at least 1.
local S = 560
-- text 560 - 20 - 20 = 520 -> 13.0 -> 13 each side
expect("wider from 20/20 (+13 each side)", pair(Layout.stepMargins({ 20, 20 }, 1, S)), "33,33")
expect("narrower from 20/20 (-13 each side)", pair(Layout.stepMargins({ 20, 20 }, -1, S)), "7,7")
-- text 560 - 160 = 400 -> 10
expect("wider from 80/80 (+10)", pair(Layout.stepMargins({ 80, 80 }, 1, S)), "90,90")
expect("narrower from 80/80 (-10)", pair(Layout.stepMargins({ 80, 80 }, -1, S)), "70,70")
-- text 560 -> 14
expect("wider from 0/0 (+14)", pair(Layout.stepMargins({ 0, 0 }, 1, S)), "14,14")
expect("narrower from 0/0: already at the limit", pair(Layout.stepMargins({ 0, 0 }, -1, S)), "nil")
-- text 560 - 280 = 280 -> 7
expect("wider from 140/140: already at the limit", pair(Layout.stepMargins({ 140, 140 }, 1, S)), "nil")
expect("narrower from 140/140 (-7)", pair(Layout.stepMargins({ 140, 140 }, -1, S)), "133,133")
-- different margins: both sides move by the same amount. text 560 - 80 = 480 -> 12
expect("wider from 0/80 (both +12)", pair(Layout.stepMargins({ 0, 80 }, 1, S)), "12,92")
expect("narrower from 0/80: the 0 side stays, the other -12", pair(Layout.stepMargins({ 0, 80 }, -1, S)), "0,68")
-- one side reaches the limit, the other has not: text 285 -> round(7.125) = 7; 135+7 = 142 -> 140, 140 stays
expect("wider from 135/140: one side reaches 140", pair(Layout.stepMargins({ 135, 140 }, 1, S)), "140,140")
-- a margin outside KOReader's range is never pushed against the direction of the step
expect("wider from 150/150: nothing to do", pair(Layout.stepMargins({ 150, 150 }, 1, S)), "nil")
local back = Layout.stepMargins({ 150, 150 }, -1, S)
expect("narrower from 150/150 moves down", back ~= nil and back[1] < 150 and back[1] >= 0 and back[1] == back[2], true)
-- a margin below KOReader's range is never pushed against the direction of the step either
-- text = 560 + 40 = 600 -> 15 each side
expect("narrower from -20/-20: it would move up, so nothing", pair(Layout.stepMargins({ -20, -20 }, -1, S)), "nil")
expect("wider from -20/-20: -5 each side", pair(Layout.stepMargins({ -20, -20 }, 1, S)), "-5,-5")
-- no room left for text at all: still a step of 1, never zero or negative
expect("text width 0: a step of 1", pair(Layout.stepMargins({ 140, 140 }, -1, 200)), "139,139")
-- bad input
expect("no margins", pair(Layout.stepMargins(nil, 1, S)), "nil")
expect("margins that are not a table", pair(Layout.stepMargins("10", 1, S)), "nil")
expect("left missing", pair(Layout.stepMargins({ nil, 10 }, 1, S)), "nil")
expect("right is text", pair(Layout.stepMargins({ 10, "x" }, 1, S)), "nil")
expect("left is NaN", pair(Layout.stepMargins({ 0 / 0, 10 }, 1, S)), "nil")
expect("no direction", pair(Layout.stepMargins({ 20, 20 }, nil, S)), "nil")
expect("direction 0", pair(Layout.stepMargins({ 20, 20 }, 0, S)), "nil")
expect("direction 2", pair(Layout.stepMargins({ 20, 20 }, 2, S)), "nil")
expect("no screen width", pair(Layout.stepMargins({ 20, 20 }, 1, nil)), "nil")
expect("screen width NaN", pair(Layout.stepMargins({ 20, 20 }, 1, 0 / 0)), "nil")
expect("screen width infinite", pair(Layout.stepMargins({ 20, 20 }, 1, math.huge)), "nil")

-- ---- font size. The step is round(5% of the size), at least 1.
expect("22 up: 1.1 -> 1", Layout.stepFontSize(22, 1), 23)
expect("22 down", Layout.stepFontSize(22, -1), 21)
expect("40 up: 2.0 -> 2", Layout.stepFontSize(40, 1), 42)
expect("40 down", Layout.stepFontSize(40, -1), 38)
expect("100 up: 5", Layout.stepFontSize(100, 1), 105)
expect("200 down: 10", Layout.stepFontSize(200, -1), 190)
expect("22.5 keeps its fraction: 1.125 -> 1", Layout.stepFontSize(22.5, 1), 23.5)
expect("12 down: at the limit", Layout.stepFontSize(12, -1), nil)
expect("12 up: 0.6 -> 1", Layout.stepFontSize(12, 1), 13)
expect("13 down: 0.65 -> 1", Layout.stepFontSize(13, -1), 12)
expect("255 up: at the limit", Layout.stepFontSize(255, 1), nil)
expect("254 up: 12.7 -> 13, stops at 255", Layout.stepFontSize(254, 1), 255)
expect("12.4 down is not allowed below 12", Layout.stepFontSize(12.4, -1), 12)
expect("a size above the range is not pushed up", Layout.stepFontSize(300, 1), nil)
expect("a size above the range comes down: 300 - 15", Layout.stepFontSize(300, -1), 285)
-- a size below the range: 5% of 5 is 0.25 -> 0, but a step is at least 1; and it is not pushed further down
expect("a size below the range goes up by at least 1", Layout.stepFontSize(5, 1), 6)
expect("a size below the range is not pushed down", Layout.stepFontSize(5, -1), nil)
expect("no size", Layout.stepFontSize(nil, 1), nil)
expect("size is text", Layout.stepFontSize("22", 1), nil)
expect("size is NaN", Layout.stepFontSize(0 / 0, 1), nil)
expect("no direction", Layout.stepFontSize(22, nil), nil)
expect("direction 0", Layout.stepFontSize(22, 0), nil)
expect("direction -2", Layout.stepFontSize(22, -2), nil)

-- ---- which buttons are usable
local c = Layout.controls({ margins = { 140, 140 }, size = 255 }, S)
expect("max everything: margins can only go narrower", c.margins_less, true)
expect("max everything: margins cannot go wider", c.margins_more, false)
expect("max everything: text can go smaller", c.text_less, true)
expect("max everything: text cannot go bigger", c.text_more, false)
c = Layout.controls({ margins = { 0, 0 }, size = 12 }, S)
expect("min everything: margins cannot go narrower", c.margins_less, false)
expect("min everything: margins can go wider", c.margins_more, true)
expect("min everything: text cannot go smaller", c.text_less, false)
expect("min everything: text can go bigger", c.text_more, true)
c = Layout.controls({ margins = { 20, 20 }, size = 22 }, S)
expect("middle: all four steps usable", c.margins_less and c.margins_more and c.text_less and c.text_more, true)
expect("there are four flags and no more (no undo any more)", (function() local n = 0 for _ in pairs(c) do n = n + 1 end return n end)(), 4)
expect("no undo flag", c.undo, nil)
c = Layout.controls(nil, S)
expect("no layout: no step", c.margins_less or c.margins_more or c.text_less or c.text_more, false)
c = Layout.controls({ margins = { 20, 20 } }, S)
expect("margins known, size missing: margins usable", c.margins_more, true)
expect("margins known, size missing: text not usable", c.text_more or c.text_less, false)

-- what the steppers show: the numbers KOReader's own menus use
expect("format: a whole number", Layout.formatNumber(22), "22")
expect("format: a float with nothing after the point has no point", Layout.formatNumber(22.0), "22")
expect("format: a half", Layout.formatNumber(22.5), "22.5")
expect("format: zero", Layout.formatNumber(0), "0")
expect("format: the biggest margin", Layout.formatNumber(140), "140")
expect("format: the biggest size", Layout.formatNumber(255), "255")
expect("format: nothing", Layout.formatNumber(nil), "")
expect("format: text is not a number", Layout.formatNumber("22"), "")
expect("format: not a number (NaN)", Layout.formatNumber(0 / 0), "")
expect("format: infinity", Layout.formatNumber(math.huge), "")
expect("margins: both sides the same show one number", Layout.formatMargins({ 10, 10 }), "10")
expect("margins: zero", Layout.formatMargins({ 0, 0 }), "0")
expect("margins: different sides show both", Layout.formatMargins({ 10, 14 }), "10/14")
expect("margins: the other way round", Layout.formatMargins({ 14, 10 }), "14/10")
expect("margins: halves", Layout.formatMargins({ 22.5, 22.5 }), "22.5")
expect("margins: one side missing", Layout.formatMargins({ 10 }), "")
expect("margins: a side that is text", Layout.formatMargins({ "10", "10" }), "")
expect("margins: not a table", Layout.formatMargins(10), "")
expect("margins: nothing", Layout.formatMargins(nil), "")

if failures > 0 then
    error(failures .. " layout test(s) failed")
end
print("layout: all tests passed")
