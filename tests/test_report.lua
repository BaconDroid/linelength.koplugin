-- Unit tests for wcount/report.lua. Run through tests/run.py (lupa), not on the device.
package.path = "./?.lua;" .. package.path
local Report = require("wcount/report")

local failures = 0
local function expect(name, got, want)
    if got ~= want then
        failures = failures + 1
        print(string.format("FAIL %s: got %q, want %q", name, tostring(got), tostring(want)))
    end
end

local LABELS = { too_long = "Too long", still_readable = "Still readable", comfortable = "Comfortable",
    excellent = "Excellent", short = "Short" }

local function build(chars)
    return Report.build({ chars = chars, chars_no_spaces = chars - 10, words = 9 }, LABELS)
end

-- the numbers are passed through
local r = build(60)
expect("chars", r.chars, 60)
expect("chars without spaces", r.chars_no_spaces, 50)
expect("words", r.words, 9)

-- the four bands, best first, with labels, ranges and colours; Comfortable has two ranges
expect("band count", #r.bands, 4)
local want = {
    { "excellent", "Excellent", "50–66", "#0072B2" },
    { "comfortable", "Comfortable", "45–49, 67–75", "#009E73" },
    { "still_readable", "Still readable", "76–80", "#E69F00" },
    { "too_long", "Too long", "81+", "#D55E00" },
}
for i, w in ipairs(want) do
    local b = r.bands[i]
    expect("band " .. i .. " id", b.id, w[1])
    expect("band " .. i .. " label", b.label, w[2])
    expect("band " .. i .. " range", b.range, w[3])
    expect("band " .. i .. " colour", b.color, w[4])
end

-- exactly one band is current, and it is the one the count falls in (edges included)
local function current(chars)
    local ids = {}
    for _i, b in ipairs(build(chars).bands) do
        if b.current then ids[#ids + 1] = b.id end
    end
    return table.concat(ids, ",")
end
expect("0 has no current band", current(0), "")
expect("44 has no current band", current(44), "")
expect("45", current(45), "comfortable")
expect("49", current(49), "comfortable")
expect("50", current(50), "excellent")
expect("66", current(66), "excellent")
expect("67", current(67), "comfortable")
expect("75", current(75), "comfortable")
expect("76", current(76), "still_readable")
expect("80", current(80), "still_readable")
expect("81", current(81), "too_long")
expect("300", current(300), "too_long")

-- the verdict
expect("tier id", r.tier.id, "excellent")
expect("tier label", r.tier.label, "Excellent")
expect("tier colour", r.tier.color, "#0072B2")
expect("60: Excellent is current", r.bands[1].current, true)
expect("60: Comfortable is not", r.bands[2].current, false)
local s = build(30)
expect("short id", s.tier.id, "short")
expect("short label", s.tier.label, "Short")
expect("short has no colour", s.tier.color, nil)
local c = build(70)
expect("70 is Comfortable", c.tier.id, "comfortable")
expect("70: Comfortable (its second range) is current", c.bands[2].current, true)

if failures > 0 then
    error(failures .. " report test(s) failed")
end
print("report: all tests passed")
