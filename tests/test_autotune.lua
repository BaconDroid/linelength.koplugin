-- Unit tests for linelength/autotune.lua. Run through tests/run.py (lupa), not on the device.
package.path = "./?.lua;" .. package.path
local AutoTune = require("linelength/autotune")

local failures = 0
local function expect(name, got, want)
    if got ~= want then
        failures = failures + 1
        print(string.format("FAIL %s: got %q, want %q", name, tostring(got), tostring(want)))
    end
end

local function expectNil(name, got)
    if got ~= nil then
        failures = failures + 1
        print(string.format("FAIL %s: got %q, want nil", name, tostring(got)))
    end
end

-- The screen of a Kobo Libra Colour, in KOReader's units: 1264 px at 2 px per unit.
local WIDTH = 632

expect("band min", AutoTune.BAND_MIN, 50)
expect("band max", AutoTune.BAND_MAX, 66)
expect("target", AutoTune.TARGET, 60)
expect("font min", AutoTune.FONT_MIN, 20)
expect("font max", AutoTune.FONT_MAX, 27)
expect("margin min", AutoTune.MARGIN_MIN, 10)
expect("margin max", AutoTune.MARGIN_MAX, 60)

expect("in band: 50", AutoTune.inBand(50), true)
expect("in band: 60", AutoTune.inBand(60), true)
expect("in band: 66", AutoTune.inBand(66), true)
expect("out of band: 49", AutoTune.inBand(49), false)
expect("out of band: 67", AutoTune.inBand(67), false)
expect("out of band: nothing", AutoTune.inBand(nil), false)
expect("out of band: text", AutoTune.inBand("x"), false)

expect("distance: in band", AutoTune.distance(60), 0)
expect("distance: at the lower edge", AutoTune.distance(50), 0)
expect("distance: too short", AutoTune.distance(45), 5)
expect("distance: too long", AutoTune.distance(70), -4)
expect("distance: nothing", AutoTune.distance(nil), 50)

local function layout(margins, size)
    return { margins = margins, size = size }
end

local next = AutoTune.next(layout({ 10, 10 }, 20), 75, WIDTH)
expect("too long: margins", next and next.margins[1], 47)
expect("too long: margins are even", next and next.margins[2], next and next.margins[1])
expect("too long: the text size does not move", next and next.size, 20)

local wider = AutoTune.next(layout({ 30, 30 }, 20), 45, WIDTH)
expect("too short: margins", wider and wider.margins[1], 10)
expect("too short: the text size does not move", wider and wider.size, 20)

local bigger = AutoTune.next(layout({ 60, 60 }, 20), 100, WIDTH)
expect("margins at their limit: the text size grows", bigger and bigger.size, 27)
expect("margins at their limit: the margins stay", bigger and bigger.margins[1], 60)

expectNil("both at their limit: nothing to try", AutoTune.next(layout({ 60, 60 }, 27), 100, WIDTH))

expectNil("text size at its limit, lines too short", AutoTune.next(layout({ 10, 10 }, 20), 40, WIDTH))

expectNil("in the band: no next step", AutoTune.next(layout({ 10, 10 }, 20), 58, WIDTH))

local clamped = AutoTune.next(layout({ 10, 10 }, 20), 200, WIDTH)
expect("a very long line: the margins stop at their limit", clamped and clamped.margins[1], 60)
local clamped2 = AutoTune.next(layout({ 10, 10 }, 20), 20, WIDTH)
expectNil("a very short line at the smallest text: nothing to try", clamped2)

local only_size = AutoTune.next(layout({ 10, 10 }, 20), 66.5, WIDTH)
expect("the lines are just over the band: the margins grow", only_size and only_size.size, 20)
expect("the lines are just over the band: the margins move", only_size and only_size.margins[1], 13)

local custom = AutoTune.next(layout({ 10, 10 }, 20), 75, WIDTH,
    { font_min = 24, font_max = 30, margin_min = 15, margin_max = 40 })
expect("custom limits: the margins stop at 40", custom and custom.margins[1], 40)
local custom2 = AutoTune.next(layout({ 40, 40 }, 24), 100, WIDTH,
    { font_min = 24, font_max = 30, margin_min = 15, margin_max = 40 })
expect("custom limits: the text size stops at 30", custom2 and custom2.size, 30)

expectNil("no layout", AutoTune.next(nil, 60, WIDTH))
expectNil("no margins", AutoTune.next({ size = 20 }, 60, WIDTH))
expectNil("no size", AutoTune.next({ margins = { 10, 10 } }, 60, WIDTH))
expectNil("no width", AutoTune.next(layout({ 10, 10 }, 20), 60, nil))
expectNil("no measurement", AutoTune.next(layout({ 10, 10 }, 20), 0, WIDTH))
expectNil("no measurement, as text", AutoTune.next(layout({ 10, 10 }, 20), "x", WIDTH))

local start = AutoTune.start(layout({ 5, 5 }, 22))
expect("start: margins below the limit come up", start.margins[1], 10)
expect("start: the text size inside the limits stays", start.size, 22)
local start2 = AutoTune.start(layout({ 90, 90 }, 40))
expect("start: margins above the limit come down", start2.margins[1], 60)
expect("start: the text size above the limit comes down", start2.size, 27)
local start3 = AutoTune.start(layout({ 15.6, 15.2 }, 22.4))
expect("start: margins are rounded", start3.margins[1], 16)
expect("start: the text size is rounded", start3.size, 22)

local function simulate(start_layout, measured)
    local current = AutoTune.start(start_layout)
    local steps = 0
    while not AutoTune.inBand(measured) and steps < 10 do
        local next_layout = AutoTune.next(current, measured, WIDTH)
        if not next_layout then break end
        local before = WIDTH - current.margins[1] - current.margins[2]
        local after = WIDTH - next_layout.margins[1] - next_layout.margins[2]
        local size_before = current.size
        current = next_layout
        steps = steps + 1
        -- The text block got narrower or wider, and the lines hold proportionally more or fewer
        -- characters, as long as the text size did not change.
        measured = math.floor(measured * after / before * size_before / current.size + 0.5)
    end
    return current, measured, steps
end

local tuned, tuned_chars, tuned_steps = simulate(layout({ 10, 10 }, 20), 75)
expect("the loop ends in the band", AutoTune.inBand(tuned_chars), true)
expect("the loop ends in one or two steps", tuned_steps <= 2, true)
expect("the loop kept the text size", tuned.size, 20)
expect("the loop widened the margins", tuned.margins[1] > 10, true)

-- Lines too short: the margins come in, and the text size drops to its floor when they cannot.
local tuned2, tuned2_chars = simulate(layout({ 10, 10 }, 26), 38)
expect("the loop made the lines longer", tuned2_chars > 38, true)
expect("the loop kept the text size at or above its floor", tuned2.size >= 20, true)
expect("the loop brought the margins in", tuned2.margins[1] <= 10, true)
-- A book whose lines are too short to ever reach the band: the smallest text and the narrowest
-- margins cannot make a line longer. The step stops instead of looping for ever.
expectNil("lines too short to reach the band: nothing to try", AutoTune.next(layout({ 10, 10 }, 20), 40, WIDTH))

if failures > 0 then
    error(failures .. " autotune test(s) failed")
end
print("autotune: all tests passed")
