-- Unit tests for wcount/pagelines.lua, against a fake document engine that behaves the way the real one
-- was measured to (see the comment at the top of that file). Run through tests/run.py (lupa).
package.path = "./?.lua;" .. package.path
local PageLines = require("wcount/pagelines")

local failures = 0
local function expect(name, got, want)
    if got ~= want then
        failures = failures + 1
        print(string.format("FAIL %s: got %q, want %q", name, tostring(got), tostring(want)))
    end
end

-- ---------------------------------------------------------------------------------------------
-- The fake engine. One text node holds the whole text; offsets count Unicode characters from 0, like
-- the real xpointers. A page is a list of lines: { vs, ve, y } = the characters [vs, ve) really drawn
-- on a line at screen height y. Selecting a line returns WHOLE words, like the real selection does.
local NODE = "/body/p[1]/text()[1]"
local H, W, LINE_H = 1680, 1264, 64

local function chars(s)
    local t = {}
    for _p, c in utf8.codes(s) do t[#t + 1] = utf8.char(c) end
    return t
end

local function newEngine(text, lines, opts)
    opts = opts or {}
    local cs = chars(text)
    local e = { calls = { text_from_positions = 0, position = 0, text_from_xpointers = 0 }, xs = {} }
    local function sub(a, b) return table.concat(cs, "", a + 1, b) end -- characters [a, b)
    local function wordStart(i) while i > 0 and cs[i] ~= " " do i = i - 1 end return cs[i + 1] == " " and i + 1 or i end
    local function wordEnd(i) -- i = index (1-based) of a character inside a word; returns offset one past the word
        while i <= #cs and cs[i] ~= " " do i = i + 1 end
        return i - 1
    end
    local function lineAt(y)
        for _i, l in ipairs(lines) do
            if y >= l.y and y < l.y + LINE_H then return l end
        end
    end
    local boxes = opts.boxes
    if not boxes then
        boxes = {}
        for _i, l in ipairs(lines) do boxes[#boxes + 1] = { x = 43, y = l.y, w = 1180, h = LINE_H } end
    end
    function e:getTextFromPositions(p0, p1, _no_draw)
        self.calls.text_from_positions = self.calls.text_from_positions + 1
        if opts.whole_nil and p0.y == 0 then return nil end
        if p0.y == 0 and p1.y == H then
            if opts.no_sboxes then return { text = "x" } end
            return { text = "page", pos0 = NODE .. ".0", pos1 = NODE .. "." .. #cs, sboxes = boxes }
        end
        self.last_x = { p0.x, p1.x }  -- where along the row the line was read
        self.xs[#self.xs + 1] = { p0.x, p1.x }
        local l = lineAt(p0.y)
        if not l or (opts.skip_line_y and l.y == opts.skip_line_y) then return nil end
        local ws = wordStart(l.vs)               -- first character of the first word on the line (0-based)
        local we = wordEnd(l.ve)                 -- one past the last character of the last word on the line
        return { text = sub(ws, we), pos0 = NODE .. "." .. ws, pos1 = NODE .. "." .. we }
    end
    function e:getScreenPositionFromXPointer(xp)
        self.calls.position = self.calls.position + 1
        if opts.position_raises then error("engine boom") end
        if opts.position_nil then return nil end
        if opts.position_wrong then return 999 end -- every character claims to be somewhere else
        local off = tonumber(xp:match("%.(%d+)$"))
        if off < lines[1].vs then return -1000, 0 end
        if off >= lines[#lines].ve then return 5000, 0 end
        for _i, l in ipairs(lines) do
            if off >= l.vs and off < l.ve then return l.y, 43 end
        end
        return 0, 0
    end
    function e:getTextFromXPointers(x0, x1)
        self.calls.text_from_xpointers = self.calls.text_from_xpointers + 1
        if opts.xpointers_nil then return nil end
        local a, b = tonumber(x0:match("%.(%d+)$")), tonumber(x1:match("%.(%d+)$"))
        return sub(a, b)
    end
    return e
end

local function lengths(lines)
    local t = {}
    for _i, l in ipairs(lines) do t[#t + 1] = l.chars end
    return table.concat(t, ",")
end
local function texts(lines)
    local t = {}
    for _i, l in ipairs(lines) do t[#t + 1] = l.text end
    return table.concat(t, "|")
end
local function numbers(lines)
    local t = {}
    for _i, l in ipairs(lines) do t[#t + 1] = tostring(l.number) end
    return table.concat(t, ",")
end

-- Offsets of "alpha beta gamma delta epsilon zeta eta theta iota kappa lambda mu" (0-based):
--   alpha 0-4  beta 6-9  gamma 11-15  delta 17-21  epsilon 23-29  zeta 31-34  eta 36-38
--   theta 40-44  iota 46-49  kappa 51-55  lambda 57-62  mu 64-65   (66 characters)
local T = "alpha beta gamma delta epsilon zeta eta theta iota kappa lambda mu"
expect("test text is 66 characters", #T, 66)

-- 1. No word is split: every line is exactly what is drawn.
--    "alpha beta gamma" = 5+1+4+1+5 = 16; "delta epsilon zeta" = 5+1+7+1+4 = 18; "eta theta iota" = 3+1+5+1+4 = 14;
--    "kappa lambda mu" = 5+1+6+1+2 = 15
local plain = {
    { vs = 0, ve = 16, y = 71 }, { vs = 17, ve = 35, y = 135 }, { vs = 36, ve = 50, y = 199 }, { vs = 51, ve = 66, y = 263 },
}
local r = PageLines.collect(newEngine(T, plain), W, H)
expect("1: four lines", #r, 4)
expect("1: lengths", lengths(r), "16,18,14,15")
expect("1: lines are numbered from the top of the page", numbers(r), "1,2,3,4")
expect("1: text of line 2", r[2].text, "delta epsilon zeta")
local e1 = newEngine(T, plain)
PageLines.collect(e1, W, H)
expect("1: no re-read of text when nothing is cut", e1.calls.text_from_xpointers, 0)
expect("1: chars without spaces of line 1", r[1].chars_no_spaces, 14)
expect("1: words of line 1", r[1].words, 3)

-- 2. "delta" is hyphenated between line 1 and line 2: de- / lta. Selecting snaps to whole words, so each
--    line would count all of "delta" (naive 22 and 18). Really drawn: "alpha beta gamma de" = 19 and
--    "lta epsilon zeta" = 3+1+7+1+4 = 16.
local hyph = { { vs = 0, ve = 19, y = 71 }, { vs = 19, ve = 35, y = 135 } }
r = PageLines.collect(newEngine(T, hyph), W, H)
expect("2: lengths cut to what is drawn", lengths(r), "19,16")
expect("2: line 1 text", r[1].text, "alpha beta gamma de")
expect("2: line 2 text", r[2].text, "lta epsilon zeta")
expect("2: the two lines add up to the 35 characters of the text (no letter twice)", r[1].chars + r[2].chars, 35)

-- 3. The page edge: the page starts in the middle of "alpha" and ends in the middle of "mu".
--    "pha beta gamma" = 3+1+4+1+5 = 14; "delta epsilon zeta" = 18; "eta theta iota" = 14; "kappa lambda m" = 5+1+6+1+1 = 14
local edge = {
    { vs = 2, ve = 16, y = 71 }, { vs = 17, ve = 35, y = 135 }, { vs = 36, ve = 50, y = 199 }, { vs = 51, ve = 65, y = 263 },
}
r = PageLines.collect(newEngine(T, edge), W, H)
expect("3: lengths, page edges cut", lengths(r), "14,18,14,14")
expect("3: first line", r[1].text, "pha beta gamma")
expect("3: last line", r[4].text, "kappa lambda m")

-- 4. A line drawn in two pieces (two boxes on the same row) is one line, not two.
local pieces = {
    { x = 43, y = 71, w = 300, h = LINE_H }, { x = 350, y = 71, w = 800, h = LINE_H },
    { x = 43, y = 135, w = 1180, h = LINE_H },
}
r = PageLines.collect(newEngine(T, { { vs = 0, ve = 16, y = 71 }, { vs = 17, ve = 35, y = 135 } }, { boxes = pieces }), W, H)
expect("4: two boxes on one row make one line", #r, 2)
expect("4: lengths", lengths(r), "16,18")
-- the merged row spans both pieces: x from 43 to 1150 (w 1107), read 8 pixels inside each end
local e4 = newEngine(T, { { vs = 0, ve = 16, y = 71 }, { vs = 17, ve = 35, y = 135 } }, { boxes = pieces })
PageLines.collect(e4, W, H)
expect("4: merged row, left edge of the sample", e4.xs[1][1], 51)
expect("4: merged row, right edge of the sample", e4.xs[1][2], 1142)
-- 4b. a box with no width is not a line
local flat = { { x = 43, y = 71, w = 1180, h = LINE_H }, { x = 0, y = 135, w = 0, h = LINE_H } }
r = PageLines.collect(newEngine(T, { { vs = 0, ve = 16, y = 71 }, { vs = 17, ve = 35, y = 135 } }, { boxes = flat }), W, H)
expect("4b: a zero-width box is skipped", lengths(r), "16")
-- the number is the line's place on the page, so a row that is skipped still counts: valid, empty, valid -> 1 and 3
local gap_boxes = {
    { x = 43, y = 71, w = 1180, h = LINE_H }, { x = 0, y = 135, w = 0, h = LINE_H }, { x = 43, y = 199, w = 1180, h = LINE_H },
}
r = PageLines.collect(newEngine(T, { { vs = 0, ve = 16, y = 71 }, { vs = 36, ve = 50, y = 199 } }, { boxes = gap_boxes }), W, H)
expect("4b: the line after a skipped row keeps its place (L1 and L3)", numbers(r), "1,3")
expect("4b: and its text is right", lengths(r), "16,14")
-- two pieces of one row are one line, so the next line is number 2, not 3
r = PageLines.collect(newEngine(T, { { vs = 0, ve = 16, y = 71 }, { vs = 17, ve = 35, y = 135 } }, { boxes = pieces }), W, H)
expect("4b: pieces of a row count once (L1, L2)", numbers(r), "1,2")

-- 5. The engine cannot say where characters are: raise, nil, or nonsense -> the whole-word counts, no crash.
for _i, mode in ipairs({ "position_raises", "position_nil" }) do
    r = PageLines.collect(newEngine(T, hyph, { [mode] = true }), W, H)
    expect("5: " .. mode .. " falls back to whole words (22 and 18)", lengths(r), "22,18")
end
-- every character claims to be elsewhere. In a text where the lines sit far from the start (offset 150+, as in
-- a real book) the scan runs into its 60-character limit: more than a word's worth in a row means the answer
-- is not trusted, and nothing is cut.
local far = ("zz "):rep(50) .. T -- 150 characters of prefix
local far_hyph = { { vs = 150, ve = 169, y = 71 }, { vs = 169, ve = 185, y = 135 } }
r = PageLines.collect(newEngine(far, far_hyph, { position_wrong = true }), W, H)
expect("5: positions that put everything elsewhere are not trusted", lengths(r), "22,18")
local e5 = newEngine(far, far_hyph, { position_wrong = true })
PageLines.collect(e5, W, H)
expect("5: it stops scanning at 60 characters per edge (4 edges)", e5.calls.position, 240)
-- the same far-away text with honest positions still cuts correctly
r = PageLines.collect(newEngine(far, far_hyph), W, H)
expect("5: far-away lines are cut like near ones", lengths(r), "19,16")
-- a long line (149 characters) with unusable positions must not lose 60 characters at each end
local long_line = ("abcdefghi "):rep(15):sub(1, -2)
expect("5: long test line is 149 characters", #long_line, 149)
local far_long = ("zz "):rep(50) .. long_line
r = PageLines.collect(newEngine(far_long, { { vs = 150, ve = 299, y = 71 } }, { position_wrong = true }), W, H)
expect("5: unusable positions leave a long line whole", lengths(r), "149")

-- 6. Re-reading the shortened text fails: keep the whole-word text of that line
r = PageLines.collect(newEngine(T, hyph, { xpointers_nil = true }), W, H)
expect("6: text re-read fails, whole words kept", lengths(r), "22,18")

-- 7. Nothing to read
expect("7: no text on the page", #PageLines.collect(newEngine(T, plain, { whole_nil = true }), W, H), 0)
expect("7: selection without boxes", #PageLines.collect(newEngine(T, plain, { no_sboxes = true }), W, H), 0)
r = PageLines.collect(newEngine(T, plain, { skip_line_y = 135 }), W, H)
expect("7: a line whose text cannot be read is skipped, the others stay", lengths(r), "16,14,15")
expect("7: the others keep their place on the page (L1, L3, L4)", numbers(r), "1,3,4")

-- 8. The same clean-up the highlight button uses is applied before counting
local spaced = "aa  bb cc"
r = PageLines.collect(newEngine(spaced, { { vs = 0, ve = 9, y = 71 } }), W, H, function(t) return (t:gsub("  +", " ")) end)
expect("8: clean-up applied (9 characters become 8)", lengths(r), "8")
expect("8: without clean-up", lengths(PageLines.collect(newEngine(spaced, { { vs = 0, ve = 9, y = 71 } }), W, H)), "9")
-- a line that is empty after the clean-up is left out
r = PageLines.collect(newEngine(T, plain), W, H, function(t) if t:find("delta", 1, true) then return "" end return t end)
expect("8: a line that cleans to nothing is skipped", lengths(r), "16,14,15")

-- 8b. a very narrow line (one short word): the row is read strictly inside it, never backwards
local narrow = { { x = 600, y = 71, w = 12, h = LINE_H } }
local en = newEngine(T, { { vs = 0, ve = 5, y = 71 } }, { boxes = narrow })
PageLines.collect(en, W, H)
expect("8b: left edge of the sample (12 wide: inset 4)", en.last_x[1], 604)
expect("8b: right edge of the sample", en.last_x[2], 608)
local wide = newEngine(T, { { vs = 0, ve = 5, y = 71 } }, { boxes = { { x = 43, y = 71, w = 1180, h = LINE_H } } })
PageLines.collect(wide, W, H)
expect("8b: a wide row is read 8 pixels inside each end", wide.last_x[1], 51)
expect("8b: right edge of a wide row", wide.last_x[2], 1215)

-- 9. Offsets are characters, not bytes: "aa éééé bb" has "éééé" at characters 3-6, split éé / éé.
--    Line 1 really shows "aa éé" (5), line 2 "éé bb" (5); whole words would give 7 and 7.
local uni = "aa éééé bb"
r = PageLines.collect(newEngine(uni, { { vs = 0, ve = 5, y = 71 }, { vs = 5, ve = 10, y = 135 } }), W, H)
expect("9: Unicode lengths counted as characters", lengths(r), "5,5")
expect("9: Unicode text", texts(r), "aa éé|éé bb")

-- ---------------------------------------------------------------------------------------------
-- longest(): the n longest lines, longest first, ties in page order
local sample = {}
for i, c in ipairs({ 10, 30, 30, 5, 20 }) do sample[i] = { chars = c, text = "L" .. i, number = i } end
local top = PageLines.longest(sample, 3)
expect("longest: three", #top, 3)
expect("longest: order with a tie kept in page order", texts(top), "L2|L3|L5")
expect("longest: each keeps its own place on the page", numbers(top), "2,3,5")
expect("longest: more asked than there are", texts(PageLines.longest(sample, 10)), "L2|L3|L5|L1|L4")
expect("longest: zero", #PageLines.longest(sample, 0), 0)
expect("longest: negative", #PageLines.longest(sample, -2), 0)
expect("longest: not a number", #PageLines.longest(sample, nil), 0)
expect("longest: no lines", #PageLines.longest({}, 3), 0)
expect("longest: the input is not reordered", texts(sample), "L1|L2|L3|L4|L5")

-- snippet(): characters, not bytes
expect("snippet: cut with an ellipsis", PageLines.snippet("hello world", 5), "hello…")
expect("snippet: exactly as long as the limit", PageLines.snippet("hello", 5), "hello")
expect("snippet: shorter than the limit", PageLines.snippet("hello", 6), "hello")
expect("snippet: empty", PageLines.snippet("", 3), "")
expect("snippet: accented characters", PageLines.snippet("héllo", 2), "hé…")
expect("snippet: three-byte characters", PageLines.snippet("日本語テキスト", 3), "日本語…")
expect("snippet: four-byte characters", PageLines.snippet("😀😀😀", 2), "😀😀…")
expect("snippet: limit 0", PageLines.snippet("abc", 0), "")
expect("snippet: not a string", PageLines.snippet(nil, 3), "")

if failures > 0 then
    error(failures .. " failure(s) in test_pagelines.lua")
end
print("test_pagelines.lua: all passed")
