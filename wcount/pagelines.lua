-- The lines on the page that is on screen, and which of them are the longest. Pure Lua: no KOReader
-- requires (the document engine is passed in), so it is tested on a desktop Lua with a fake engine.
-- LuaJIT/Lua 5.1 safe (no goto, no bit operators, no utf8 library).
--
-- Why the correction below exists: selecting a line of text in KOReader snaps to whole words, so a
-- word that is hyphenated across a line break (or across the page break) is counted on BOTH of its
-- lines. Measured on a test book, that made the longest line read 63 characters when it really
-- was 55. The engine can say where each character sits on screen, so for the first and the last
-- word of every line we ask which of its characters really are on that line and cut the rest.
--
-- The engine object needs three methods (CreDocument has them):
--   getTextFromPositions(pos0, pos1, true) -> { text, pos0, pos1, sboxes = { {x,y,w,h}, ... } } or nil
--   getScreenPositionFromXPointer(xpointer) -> y, x   (screen y first; off the page it is outside it)
--   getTextFromXPointers(xpointer0, xpointer1) -> string
local Counter = require("wcount/counter")

local PageLines = {}

-- How many characters at the edge of a line are checked for being on another line. A word is never
-- this long; if that many in a row look misplaced, the positions cannot be trusted and nothing is cut.
local MAX_SCAN = 60

-- "<node path>.<offset>" -> "<node path>", offset
local function splitPointer(xp)
    if type(xp) ~= "string" then
        return nil
    end
    local node, offset = xp:match("^(.*)%.(%d+)$")
    if not node then
        return nil
    end
    return node, tonumber(offset)
end

-- Is the character at node/offset drawn on this line? Unknown (a failed call) counts as "yes", so
-- that a broken engine call never cuts anything.
local function onLine(doc, line, node, offset)
    local ok, y = pcall(doc.getScreenPositionFromXPointer, doc, node .. "." .. offset)
    if not ok or type(y) ~= "number" then
        return true
    end
    return math.abs(y - line.y) < line.h / 2
end

-- How many characters from the start of the line belong to an earlier line.
local function cutAtStart(doc, line)
    local node, first = splitPointer(line.pos0)
    if not node then
        return 0
    end
    local n = 0
    while n < MAX_SCAN and not onLine(doc, line, node, first + n) do
        n = n + 1
    end
    if n >= MAX_SCAN then
        return 0
    end
    return n
end

-- How many characters at the end of the line belong to a later line.
local function cutAtEnd(doc, line)
    local node, stop = splitPointer(line.pos1) -- stop is one past the last character
    if not node then
        return 0
    end
    local n = 0
    while n < MAX_SCAN and stop - 1 - n >= 0 and not onLine(doc, line, node, stop - 1 - n) do
        n = n + 1
    end
    if n >= MAX_SCAN then
        return 0
    end
    return n
end

-- The text of the line without the characters that are drawn on its neighbours; the original text
-- when nothing is cut or the engine cannot say.
local function visibleText(doc, line)
    local cut_start, cut_end = cutAtStart(doc, line), cutAtEnd(doc, line)
    if cut_start == 0 and cut_end == 0 then
        return line.text
    end
    local node0, first = splitPointer(line.pos0)
    local node1, stop = splitPointer(line.pos1)
    if node0 == node1 and first + cut_start >= stop - cut_end then
        return line.text
    end
    local ok, text = pcall(doc.getTextFromXPointers, doc,
        node0 .. "." .. (first + cut_start), node1 .. "." .. (stop - cut_end))
    if ok and type(text) == "table" then
        text = text.text
    end
    if ok and type(text) == "string" and text ~= "" then
        return text
    end
    return line.text
end

-- Boxes on the same row (a line drawn in several pieces) become one box.
local function mergeRows(boxes)
    local rows = {}
    for _i, b in ipairs(boxes) do
        local row = rows[#rows]
        if row and math.abs(b.y - row.y) < row.h / 2 then
            local right = math.max(row.x + row.w, b.x + b.w)
            row.x = math.min(row.x, b.x)
            row.w = right - row.x
        else
            rows[#rows + 1] = { x = b.x, y = b.y, w = b.w, h = b.h }
        end
    end
    return rows
end

--- Read the lines of the page on screen.
-- @param doc the document engine (see the top of this file)
-- @param width, height the screen size in pixels
-- @param clean optional function(text) -> text, applied before counting (KOReader's own clean-up of a
--        selection, so the numbers match what the highlight button counts)
-- @return list, top to bottom, of { number, text, chars, chars_no_spaces, words }; `number` is the line's
--         position on the page counted from the top (1 = the first line), so it still matches what you see
--         when a line in between could not be read. An empty list when the page has no text.
function PageLines.collect(doc, width, height, clean)
    local ok, whole = pcall(doc.getTextFromPositions, doc, { x = 0, y = 0 }, { x = width, y = height }, true)
    if not ok or type(whole) ~= "table" or type(whole.sboxes) ~= "table" then
        return {}
    end
    local lines = {}
    for number, row in ipairs(mergeRows(whole.sboxes)) do
        if row.w > 0 and row.h > 0 then
            local inset = math.min(8, math.floor(row.w / 3))
            local mid = row.y + math.floor(row.h / 2)
            local ok_line, one = pcall(doc.getTextFromPositions, doc,
                { x = row.x + inset, y = mid }, { x = row.x + row.w - inset, y = mid }, true)
            if ok_line and type(one) == "table" and type(one.text) == "string" and one.text ~= "" then
                local line = { text = one.text, pos0 = one.pos0, pos1 = one.pos1, y = row.y, h = row.h }
                local text = visibleText(doc, line)
                if clean then
                    text = clean(text)
                end
                local counts = Counter.count(text)
                if counts.chars > 0 then
                    lines[#lines + 1] = {
                        number = number,
                        text = text,
                        chars = counts.chars,
                        chars_no_spaces = counts.chars_no_spaces,
                        words = counts.words,
                    }
                end
            end
        end
    end
    return lines
end

--- The n longest lines, longest first; equal lengths keep their order on the page.
function PageLines.longest(lines, n)
    local order = {}
    for i = 1, #lines do
        order[i] = i
    end
    table.sort(order, function(a, b)
        if lines[a].chars ~= lines[b].chars then
            return lines[a].chars > lines[b].chars
        end
        return a < b
    end)
    local out = {}
    for i = 1, math.min(math.max(math.floor(tonumber(n) or 0), 0), #order) do
        out[i] = lines[order[i]]
    end
    return out
end

--- The first `max` characters of a text, with an ellipsis when it was cut. Counts Unicode characters,
-- not bytes, so it never cuts one in half.
function PageLines.snippet(text, max)
    if type(text) ~= "string" or max < 1 then
        return ""
    end
    local i, n, len = 1, 0, #text
    while i <= len do
        local c = text:byte(i)
        local size = 1
        if c >= 0xF0 then
            size = 4
        elseif c >= 0xE0 then
            size = 3
        elseif c >= 0xC0 then
            size = 2
        end
        if n == max then
            return text:sub(1, i - 1) .. "…"
        end
        n = n + 1
        i = i + size
    end
    return text
end

return PageLines
