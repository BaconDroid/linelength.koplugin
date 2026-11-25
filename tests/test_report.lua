package.path = "./?.lua;" .. package.path
local Report = require("linelength/report")

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

-- the four bands, best first, with labels, ranges and colours
expect("band count", #r.bands, 4)
local want = {
    { "excellent", "Excellent", "50–66", "#0072B2" },
    { "comfortable", "Comfortable", "67–75", "#009E73" },
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
expect("45 has no current band (short)", current(45), "")
expect("49 has no current band (short)", current(49), "")
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
local s49 = build(49)
expect("49 is Short", s49.tier.id, "short")
local c = build(70)
expect("70 is Comfortable", c.tier.id, "comfortable")
expect("70: Comfortable is current", c.bands[2].current, true)

-- ---- a whole page: buildPage ----------------------------------------------------------------
local function line(chars, text, number)
    return { chars = chars, chars_no_spaces = chars, words = 1, text = text or string.rep("x", chars), number = number }
end
local page = Report.buildPage({ line(70, nil, 7), line(59, nil, 2), line(45, nil, 19) }, LABELS)
-- each listed line carries its own place on the page, as given: it is not the position in the list
expect("page: first listed line is line 7 of the page", page.lines[1].number, 7)
expect("page: second listed line is line 2 of the page", page.lines[2].number, 2)
expect("page: third listed line is line 19 of the page", page.lines[3].number, 19)
expect("page: the rating is the longest line's (70)", page.chars, 70)
expect("page: verdict", page.tier.id, "comfortable")
expect("page: verdict label", page.tier.label, "Comfortable")
expect("page: verdict colour", page.tier.color, "#009E73")
expect("page: four ranges, Comfortable current", page.bands[2].current, true)
expect("page: other ranges not current", page.bands[1].current or page.bands[3].current or page.bands[4].current, false)
expect("page: three lines", #page.lines, 3)
expect("page: line 1 length", page.lines[1].chars, 70)
expect("page: line 2 length", page.lines[2].chars, 59)
expect("page: line 3 length", page.lines[3].chars, 45)
-- the rating comes from the first line given, not from the others
expect("page: the first line decides (49 is Short even if others are longer)",
    Report.buildPage({ line(49), line(90) }, LABELS).tier.id, "short")
expect("page: a single line", #Report.buildPage({ line(60) }, LABELS).lines, 1)
-- the start of each line's text: 32 characters fit, more are cut with an ellipsis
expect("page: 32 characters are not cut", Report.buildPage({ line(32, string.rep("a", 32)) }, LABELS).lines[1].snippet, string.rep("a", 32))
expect("page: 33 characters are cut to 32 and an ellipsis",
    Report.buildPage({ line(33, string.rep("a", 33)) }, LABELS).lines[1].snippet, string.rep("a", 32) .. "…")
expect("page: accented text is cut by characters, not bytes",
    Report.buildPage({ line(40, string.rep("é", 40)) }, LABELS).lines[1].snippet, string.rep("é", 32) .. "…")
-- selection reports have no list of lines
expect("selection report has no lines", build(60).lines, nil)
-- building a page report does not change what build gives for the same line
local plain = Report.build(line(70), LABELS)
expect("page: same bands as build", #page.bands, #plain.bands)
expect("page: same range text", page.bands[3].range, plain.bands[3].range)

if failures > 0 then
    error(failures .. " report test(s) failed")
end
print("report: all tests passed")
