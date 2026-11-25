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
expect("band max", AutoTune.BAND_MAX, 60)
expect("target", AutoTune.TARGET, 60)
expect("margin min", AutoTune.MARGIN_MIN, 10)
expect("margin max", AutoTune.MARGIN_MAX, 60)
expect("characters per step", AutoTune.MAX_CHARS_PER_STEP, 6)

expect("in band: 50", AutoTune.inBand(50), true)
expect("in band: 60", AutoTune.inBand(60), true)
expect("in band: 60", AutoTune.inBand(60), true)
expect("out of band: 49", AutoTune.inBand(49), false)
expect("out of band: 61", AutoTune.inBand(61), false)
expect("out of band: nothing", AutoTune.inBand(nil), false)
expect("out of band: text", AutoTune.inBand("x"), false)

expect("distance: in band", AutoTune.distance(60), 0)
expect("distance: at the lower edge", AutoTune.distance(50), 0)
expect("distance: too short", AutoTune.distance(45), 5)
expect("distance: too long", AutoTune.distance(70), -10)
expect("distance: nothing", AutoTune.distance(nil), 50)

local wider = AutoTune.nextMargin(10, 80, WIDTH)
expect("too long: the margins widen", wider > 10, true)
expect("too long: by at least a step", wider >= 12, true)

local narrower = AutoTune.nextMargin(40, 40, WIDTH)
expect("too short: the margins come in", narrower < 40, true)
expect("too short: by at least a step", narrower <= 38, true)

expectNil("margins at their limit: nothing to try", AutoTune.nextMargin(60, 100, WIDTH))
expectNil("margins at their minimum: nothing to try", AutoTune.nextMargin(10, 30, WIDTH))

-- A wide margin and very long lines: the bound is what stops the margins.
local capped = AutoTune.nextMargin(50, 120, WIDTH, { margin_max = 60 })
expect("the bound stops the margins", capped, 60)
local uncapped = AutoTune.nextMargin(50, 120, WIDTH, { margin_max = 140 })
expect("a wider bound lets the margins go further", uncapped > capped, true)
-- A bigger step moves the margins further in one go.
local bigger_step = AutoTune.nextMargin(10, 80, WIDTH, { max_chars_per_step = 20 })
expect("a bigger step moves further", bigger_step > wider, true)

local wanted = AutoTune.nextMargin(10, 80, WIDTH)
local second = AutoTune.nextMargin(wanted, 80, WIDTH)
expect("the step is bounded", wanted - 10 <= 25, true)
expect("the next step goes on", second >= wanted or second == nil, true)

expectNil("no margin", AutoTune.nextMargin(nil, 60, WIDTH))
expectNil("no measurement", AutoTune.nextMargin(10, 0, WIDTH))
expectNil("no measurement, as text", AutoTune.nextMargin(10, "x", WIDTH))
expectNil("no width", AutoTune.nextMargin(10, 60, nil))

expect("start: a margin below the bound comes up", AutoTune.startMargin(5), 10)
expect("start: a margin above the bound comes down", AutoTune.startMargin(90), 60)
expect("start: a margin inside the bounds stays", AutoTune.startMargin(25), 25)
expect("start: a margin is rounded", AutoTune.startMargin(25.6), 26)
expect("start: no margin at all", AutoTune.startMargin(nil), 10)

-- The loop the way the plugin runs it: the margins move by steps, each one measured, until the line
-- length is in the band. The screen is 632 units wide.
-- The characters a line holds, from the real relation measured on a book: a line of 59 characters
-- in a block of 612 units. The block is the screen minus the margins.
local function chars_in(block)
    return math.floor(block * 59 / 612 + 0.5)
end

local function simulate(start_margin, measured)
    local margin = AutoTune.startMargin(start_margin)
    local steps = 0
    while not AutoTune.inBand(measured) and steps < 20 do
        local next_margin = AutoTune.nextMargin(margin, measured, WIDTH)
        if not next_margin then break end
        margin = next_margin
        steps = steps + 1
        measured = chars_in(WIDTH - 2 * margin)
    end
    return margin, measured, steps
end

local margin, chars, steps = simulate(10, 80)
expect("the loop ends in the band", AutoTune.inBand(chars), true)
expect("the loop ends in a few steps", steps <= 3, true)
expect("the loop widened the margins", margin > 10, true)
expect("the loop stayed inside the bounds", margin <= 60, true)

local margin2, chars2, steps2 = simulate(60, 40)
expect("the loop ends in the band from the other side", AutoTune.inBand(chars2), true)
expect("the loop brought the margins in", margin2 < 60, true)
expect("the loop ends in a few steps there too", steps2 <= 3, true)

-- A book whose lines cannot reach the band at any margin: the loop stops instead of going for ever.
local margin3, chars3, steps3 = simulate(60, 90)
expect("an unreachable band stops the loop", steps3 < 20, true)

if failures > 0 then
    error(failures .. " autotune test(s) failed")
end
print("autotune: all tests passed")
