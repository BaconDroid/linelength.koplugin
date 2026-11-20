-- Builds what the details card shows from the counts of a selection. Pure Lua: no KOReader
-- requires, so it is tested on a desktop Lua. Labels are passed in so the caller can translate them.
local Rating = require("wcount/rating")
local PageLines = require("wcount/pagelines")

local Report = {}

-- How many characters of a line are shown to tell it apart from the others on the page.
local SNIPPET_CHARS = 32

local function rangeText(band)
    if band.max then
        return string.format("%d–%d", band.min, band.max)
    end
    return string.format("%d+", band.min)
end

--- @param counts table { words, chars, chars_no_spaces } as returned by wcount/counter
--- @param labels table band id -> display label (too_long, still_readable, comfortable, excellent, short)
--- @return table { chars, chars_no_spaces, words, tier = { id, label, color }, bands = { { id, label, range, color, current }, ... } }
--- `bands` runs from the best band to the worst and leaves out "short", which has no range of its own.
function Report.build(counts, labels)
    local tier = Rating.forChars(counts.chars)
    local bands = {}
    for _i, band in ipairs(Rating.BANDS) do
        bands[#bands + 1] = {
            id = band.id,
            label = labels[band.id],
            range = rangeText(band),
            color = band.color,
            current = band.id == tier.id,
        }
    end
    return {
        chars = counts.chars,
        chars_no_spaces = counts.chars_no_spaces,
        words = counts.words,
        tier = { id = tier.id, label = labels[tier.id], color = tier.color },
        bands = bands,
    }
end

--- The report for a whole page: the rating is the one of the longest line, and `lines` lists the longest
-- lines with their number on the page and the start of their text, so they can be found on the page.
--- @param top table the longest lines, longest first, from wcount/pagelines (never empty)
--- @param labels table as for build
--- @return table what build returns for the longest line, plus lines = { { number, chars, snippet }, ... }
function Report.buildPage(top, labels)
    local report = Report.build(top[1], labels)
    report.lines = {}
    for i, line in ipairs(top) do
        report.lines[i] = {
            number = line.number,
            chars = line.chars,
            snippet = PageLines.snippet(line.text, SNIPPET_CHARS),
        }
    end
    return report
end

return Report
