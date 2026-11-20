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

-- the four ranges, lowest first, with the spec'd labels and colours
expect("band count", #r.bands, 4)
local want = {
    { "excellent", "Excellent", "45–54", "#0072B2" },
    { "comfortable", "Comfortable", "55–64", "#009E73" },
    { "still_readable", "Still readable", "65–74", "#E69F00" },
    { "too_long", "Too long", "75+", "#D55E00" },
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
expect("44 has no current band", current(44), "")
expect("45", current(45), "excellent")
expect("54", current(54), "excellent")
expect("55", current(55), "comfortable")
expect("64", current(64), "comfortable")
expect("65", current(65), "still_readable")
expect("74", current(74), "still_readable")
expect("75", current(75), "too_long")
expect("300", current(300), "too_long")
expect("0", current(0), "")

-- the verdict
expect("tier id", r.tier.id, "comfortable")
expect("tier label", r.tier.label, "Comfortable")
expect("tier colour", r.tier.color, "#009E73")
local s = build(30)
expect("short id", s.tier.id, "short")
expect("short label", s.tier.label, "Short")
expect("short has no colour", s.tier.color, nil)

if failures > 0 then
    error(failures .. " report test(s) failed")
end
print("report: all tests passed")
