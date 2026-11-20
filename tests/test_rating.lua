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

-- Every edge. Bands: under 50 short; 50-66 Excellent; 67-75 Comfortable; 76-80 Still readable;
-- 81+ Too long.
local cases = {
    { 0, "short", nil },
    { 1, "short", nil },
    { 44, "short", nil },
    { 45, "short", nil },
    { 49, "short", nil },
    { 50, "excellent", "#0072B2" },
    { 66, "excellent", "#0072B2" },
    { 67, "comfortable", "#009E73" },
    { 75, "comfortable", "#009E73" },
    { 76, "still_readable", "#E69F00" },
    { 80, "still_readable", "#E69F00" },
    { 81, "too_long", "#D55E00" },
    { 500, "too_long", "#D55E00" },
}
for _i, c in ipairs(cases) do
    local tier = Rating.forChars(c[1])
    expect("band for " .. c[1], tier.id, c[2])
    expect("colour for " .. c[1], tier.color, c[3])
end

-- bad input never fails and counts as short; fractions round down
expect("nil", Rating.forChars(nil).id, "short")
expect("negative", Rating.forChars(-5).id, "short")
expect("not a number", Rating.forChars("abc").id, "short")
expect("numeric string", Rating.forChars("60").id, "excellent")
expect("fraction rounds down (66.5 is 66)", Rating.forChars(66.5).id, "excellent")
expect("fraction rounds down (49.9 is 49)", Rating.forChars(49.9).id, "short")

-- exactly one answer for every count 0..300, checked against an independent if-chain, and the
-- totals worked out by hand: short 0-49 = 50, excellent 50-66 = 17, comfortable 67-75 = 9,
-- still readable 76-80 = 5, too long 81-300 = 220 (50+17+9+5+220 = 301)
local function expected(n)
    if n < 50 then return "short" end
    if n <= 66 then return "excellent" end
    if n <= 75 then return "comfortable" end
    if n <= 80 then return "still_readable" end
    return "too_long"
end
local totals = {}
for n = 0, 300 do
    local id = Rating.forChars(n).id
    expect("oracle at " .. n, id, expected(n))
    totals[id] = (totals[id] or 0) + 1
end
expect("total short", totals.short, 50)
expect("total excellent", totals.excellent, 17)
expect("total comfortable", totals.comfortable, 9)
expect("total still readable", totals.still_readable, 5)
expect("total too long", totals.too_long, 220)

-- the best band comes first, "short" is not one of the listed bands
local ids = {}
for _i, band in ipairs(Rating.BANDS) do ids[#ids + 1] = band.id end
expect("band order", table.concat(ids, ","), "excellent,comfortable,still_readable,too_long")

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
for _i, band in ipairs(Rating.BANDS) do
    expect("table colour parses: " .. band.id, Rating.parseHex(band.color) ~= nil, true)
end

if failures > 0 then
    error(failures .. " rating test(s) failed")
end
print("rating: all tests passed")
