-- Test of linelength/pagelines.lua against KOReader's REAL text engine (crengine), headless, on the books made by
-- tests/fixtures/make_epub.py. For every page the corrected line lengths must add up exactly to the text
-- of that page as crengine itself defines it (from this page's start to the next page's start): no
-- character counted twice, none lost. It also shows how far the longest line is overstated without the
-- correction. Needs the macOS KOReader build (see tests/render.lua for how to get it):
--   cd <KOReader.app>/Contents/koreader
--   HOME=<empty dir> PLUGIN_DIR=<this repo> BOOK_DIR=<dir with justified.epub and ragged.epub> \
--     SDL_VIDEODRIVER=dummy EMULATE_READER_W=1264 EMULATE_READER_H=1680 EMULATE_READER_DPI=300 \
--     ./luajit <this repo>/tests/engine.lua
io.stdout:setvbuf("line")
os.setlocale("C", "numeric")
require("setupkoenv")
G_defaults = require("luadefaults"):open()
local DataStorage = require("datastorage")
G_reader_settings = require("luasettings"):open(DataStorage:getDataDir() .. "/settings.reader.lua")
local Device = require("device")
require("document/canvascontext"):init(Device)
require("ui/bidi").setup(nil)
local Screen = Device.screen
local util = require("util")

package.path = os.getenv("PLUGIN_DIR") .. "/?.lua;" .. package.path
local PageLines = require("linelength/pagelines")
local Counter = require("linelength/counter")

local W, H = Screen:getWidth(), Screen:getHeight()
local failures, pages_total, pages_ok, overstated_pages, max_overstatement, lines_total = 0, 0, 0, 0, 0, 0
local slowest = 0

local function check(name, ok, detail)
    if not ok then
        failures = failures + 1
        print("FAIL " .. name .. (detail and ("  (" .. detail .. ")") or ""))
    end
end

-- the engine with the position lookup switched off: what the lines would be without the correction
local function naive(doc)
    return setmetatable({ getScreenPositionFromXPointer = function() return nil end }, { __index = doc })
end

-- The independent oracle for the line numbers: the rows of the page as the engine reports them for the text
-- between this page's start and the next page's start (a different call from the one pagelines uses), each
-- row's raw text read back at its own height. Row N here must be the line the plugin calls N.
local function oracleRows(doc, from, to)
    local boxes = doc:getScreenBoxesFromPositions(from, to) or {}
    table.sort(boxes, function(a, b) return a.y < b.y end)
    -- The engine hands back the last line of a paragraph and the first line of the next one as ONE box twice
    -- as tall as a line (seen: y=837 h=104 for the rows at y=837 and y=889). A box that is a whole number of
    -- line heights tall is split back into its lines, by plain arithmetic.
    local line_h = math.huge
    for _i, b in ipairs(boxes) do line_h = math.min(line_h, b.h) end
    local split = {}
    for _i, b in ipairs(boxes) do
        local n = math.max(1, math.floor(b.h / line_h + 0.5))
        for k = 0, n - 1 do
            split[#split + 1] = { x = b.x, y = b.y + math.floor(k * b.h / n), w = b.w, h = math.floor(b.h / n) }
        end
    end
    boxes = split
    local rows = {}
    for _i, b in ipairs(boxes) do
        local last = rows[#rows]
        if last and b.y < last.y + last.h / 2 then
            local x2 = math.max(last.x + last.w, b.x + b.w)
            last.x = math.min(last.x, b.x)
            last.w = x2 - last.x
        else
            rows[#rows + 1] = { x = b.x, y = b.y, w = b.w, h = b.h }
        end
    end
    for _i, r in ipairs(rows) do
        local mid = r.y + math.floor(r.h / 2)
        local got = doc:getTextFromPositions({ x = r.x + 8, y = mid }, { x = r.x + r.w - 8, y = mid }, true)
        r.raw = got and got.text or ""
    end
    return rows
end
-- A line's inner text (everything but its first and last word) must be inside the raw text of the oracle's row.
-- The edge words are left out on purpose: the raw read drops an opening quote, and a word cut at a page or line
-- break is read whole or not at all. What is left is nearly the whole line, and differs from every other row.
-- (A line of one or two words has no inner text: all of it is compared.)
local function sameRow(line, row)
    if not row then return false end
    local inner = line.text:match("^%S+%s+(.-)%s+%S+$") or line.text
    return row.raw:find(inner, 1, true) ~= nil
end
local numbered_ok, numbered_total, listed_ok, listed_total = 0, 0, 0, 0

for _i, book in ipairs({ "justified", "ragged" }) do
    for _j, size in ipairs({ 18, 22, 30 }) do
        local doc = require("document/documentregistry"):openDocument(os.getenv("BOOK_DIR") .. "/" .. book .. ".epub")
        doc:setViewDimen(Screen:getSize())
        doc:setFontFace("Noto Serif")
        doc:setFontSize(Screen:scaleBySize(size))
        doc:setPageMargins(Screen:scaleBySize(20), Screen:scaleBySize(20), Screen:scaleBySize(20), Screen:scaleBySize(20))
        doc:render()
        local pages = doc:getPageCount()
        local book_ok, book_pages = 0, 0
        for page = 1, pages do
            doc:gotoPage(page)
            local t0 = os.clock()
            local lines = PageLines.collect(doc, W, H, util.cleanupSelectedText)
            slowest = math.max(slowest, os.clock() - t0)
            local plain = PageLines.collect(naive(doc), W, H, util.cleanupSelectedText)

            local sum = 0
            local longest, longest_naive = 0, 0
            for _k, l in ipairs(lines) do
                sum = sum + l.chars_no_spaces
                longest = math.max(longest, l.chars)
            end
            for _k, l in ipairs(plain) do longest_naive = math.max(longest_naive, l.chars) end
            -- reference: the text between this page's start and the next page's start
            local from = doc:getPageXPointer(page)
            local to = page < pages and doc:getPageXPointer(page + 1) or nil
            if not to then
                local whole = doc:getTextFromPositions({ x = 0, y = 0 }, { x = W, y = H }, true)
                to = whole and whole.pos1
            end
            local reference = Counter.count(doc:getTextFromXPointers(from, to)).chars_no_spaces

            -- line numbers: 1, 2, 3 ... from the top, each the row the oracle calls that number
            local rows = oracleRows(doc, from, to)
            check(string.format("%s %dpt page %d: as many rows as lines", book, size, page), #rows == #lines,
                string.format("%d rows, %d lines", #rows, #lines))
            for k, l in ipairs(lines) do
                numbered_total = numbered_total + 1
                local good = l.number == k and sameRow(l, rows[l.number])
                if good then numbered_ok = numbered_ok + 1 end
                check(string.format("%s %dpt page %d line %d is row %s", book, size, page, k, tostring(l.number)), good,
                    string.format("text %q | oracle row %s raw %q (y=%s w=%s)", l.text, tostring(rows[l.number] and rows[l.number].y),
                        rows[l.number] and rows[l.number].raw or "none", tostring(rows[l.number] and rows[l.number].y), tostring(rows[l.number] and rows[l.number].w)))
            end
            -- the lines the card lists (longest first): each keeps the number of its own place on the page
            for rank, l in ipairs(PageLines.longest(lines, 3)) do
                listed_total = listed_total + 1
                local good = sameRow(l, rows[l.number])
                if good then listed_ok = listed_ok + 1 end
                check(string.format("%s %dpt page %d listed #%d (L%s) is that row", book, size, page, rank, tostring(l.number)), good)
            end

            book_pages = book_pages + 1
            pages_total = pages_total + 1
            lines_total = lines_total + #lines
            local balanced = sum == reference
            if balanced then book_ok = book_ok + 1; pages_ok = pages_ok + 1 end
            check(string.format("%s %dpt page %d balances", book, size, page), balanced,
                string.format("lines add up to %d, the page has %d", sum, reference))
            -- the correction can only ever make a line shorter
            check(string.format("%s %dpt page %d: corrected longest <= naive longest", book, size, page), longest <= longest_naive)
            if longest_naive > longest then
                overstated_pages = overstated_pages + 1
                max_overstatement = math.max(max_overstatement, longest_naive - longest)
            end
            check(string.format("%s %dpt page %d has lines", book, size, page), #lines > 0)
        end
        print(string.format("%-9s %2dpt: %d pages, %d balance exactly", book, size, book_pages, book_ok))
    end
end

print(string.format("TOTAL: %d lines on %d pages; %d pages balance exactly", lines_total, pages_total, pages_ok))
print(string.format("line numbers: %d of %d lines are the row of the page the independent oracle gives them", numbered_ok, numbered_total))
print(string.format("listed longest lines: %d of %d point at their own row", listed_ok, listed_total))
print(string.format("without the correction the longest line was too long on %d pages, by up to %d characters", overstated_pages, max_overstatement))
print(string.format("slowest page: %.0f ms", slowest * 1000))
check("at least one page needed the correction (otherwise this test proves nothing)", overstated_pages > 0)
if failures > 0 then print(failures .. " FAILURE(S)"); os.exit(1) end
print("all checks passed")
os.exit(0)
