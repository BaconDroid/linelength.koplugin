-- Builds what the details card shows from the counts of a selection. Pure Lua: no KOReader
-- requires, so it is tested on a desktop Lua. Labels are passed in so the caller can translate them.
local Rating = require("wcount/rating")

local Report = {}

--- @param counts table { words, chars, chars_no_spaces } as returned by wcount/counter
--- @param labels table band id -> display label (too_long, still_readable, comfortable, excellent, short)
--- @return table { chars, chars_no_spaces, words, tier = { id, label, color }, bands = { { id, label, range, color, current }, ... } }
--- `bands` runs from the lowest band to the highest and leaves out "short", which has no range of its own.
function Report.build(counts, labels)
    local tier = Rating.forChars(counts.chars)
    local tiers = Rating.TIERS
    local bands = {}
    for i = #tiers - 1, 1, -1 do
        local band = tiers[i]
        local upper = tiers[i - 1] and (tiers[i - 1].min - 1)
        bands[#bands + 1] = {
            id = band.id,
            label = labels[band.id],
            range = upper and string.format("%d–%d", band.min, upper) or string.format("%d+", band.min),
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

return Report
