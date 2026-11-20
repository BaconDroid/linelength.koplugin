-- Unit tests for wcount/rating.lua. Run through tests/run.py (lupa), not on the device.
package.path = "./?.lua;" .. package.path
local Rating = require("wcount/rating")

local failures = 0
local function expect(name, got, want)
    if got ~= want then
        failures = failures + 1
        print(string.format("FAIL %s: got %q, want %q", name, tostring(got), tostring(want)))
    end
end

-- Every band edge, as specified: 45-54 Excellent, 55-64 Comfortable, 65-74 Still readable, 75+ Too long
local cases = {
    { 0, "short", nil },
    { 1, "short", nil },
    { 44, "short", nil },
    { 45, "excellent", "#0072B2" },
    { 54, "excellent", "#0072B2" },
    { 55, "comfortable", "#009E73" },
    { 64, "comfortable", "#009E73" },
    { 65, "still_readable", "#E69F00" },
    { 74, "still_readable", "#E69F00" },
    { 75, "too_long", "#D55E00" },
    { 76, "too_long", "#D55E00" },
    { 500, "too_long", "#D55E00" },
}
for _i, c in ipairs(cases) do
    local tier = Rating.forChars(c[1])
    expect("band for " .. c[1], tier.id, c[2])
    expect("colour for " .. c[1], tier.color, c[3])
end

-- bad input never fails and counts as short
expect("nil", Rating.forChars(nil).id, "short")
expect("negative", Rating.forChars(-5).id, "short")
expect("not a number", Rating.forChars("abc").id, "short")
expect("numeric string", Rating.forChars("60").id, "comfortable")

-- exactly one band per count and bands never go down as the count goes up
local order = { short = 0, excellent = 1, comfortable = 2, still_readable = 3, too_long = 4 }
local previous = 0
for n = 0, 300 do
    local rank = order[Rating.forChars(n).id]
    if rank == nil or rank < previous then
        failures = failures + 1
        print("FAIL band order broke at " .. n)
        break
    end
    previous = rank
end

-- hex parsing: the four colours from the spec, and bad input
local function rgb(hex)
    local r, g, b = Rating.parseHex(hex)
    return r .. "," .. g .. "," .. b
end
expect("#0072B2", rgb("#0072B2"), "0,114,178")
expect("#009E73", rgb("#009E73"), "0,158,115")
expect("#E69F00", rgb("#E69F00"), "230,159,0")
expect("#D55E00", rgb("#D55E00"), "213,94,0")
expect("lower case hex", rgb("#d55e00"), "213,94,0")
expect("missing #", Rating.parseHex("0072B2"), nil)
expect("too short", Rating.parseHex("#0072B"), nil)
expect("not hex", Rating.parseHex("#GG72B2"), nil)
expect("nil hex", Rating.parseHex(nil), nil)
expect("number", Rating.parseHex(123456), nil)

-- every colour in the table must parse
for _i, tier in ipairs(Rating.TIERS) do
    if tier.color then
        expect("table colour parses: " .. tier.id, Rating.parseHex(tier.color) ~= nil, true)
    end
end

if failures > 0 then
    error(failures .. " rating test(s) failed")
end
print("rating: all tests passed")
