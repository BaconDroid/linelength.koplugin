-- Line-length rating for the Word count plugin. Pure Lua: no KOReader requires.
--
-- The number of characters of a selected line (spaces and symbols included) is mapped to a band.
-- The edges come from published guidance on "measure" (characters per line); see the README for
-- the sources:
--   45        Bringhurst: 45 to 75 is satisfactory for a single column of text.
--   50        Baymard: 50 to 75 for body text; Ruder: 50 to 60 is optimal.
--   66        Bringhurst: the 66-character line is ideal.
--   75        Bringhurst and Baymard: the upper end of the satisfactory range.
--   80        WCAG 1.4.8: lines should not exceed 80 characters.
--
-- Excellent is the zone the sources agree on. Comfortable is acceptable but off the ideal, on both
-- sides of it. Under 45 is "short" and has no colour: it is shown in the normal text colour.
local Rating = {}

-- In order of quality. A band can have several ranges; a range without `max` is open-ended.
Rating.BANDS = {
    { id = "excellent",      color = "#0072B2", ranges = { { min = 50, max = 66 } } },
    { id = "comfortable",    color = "#009E73", ranges = { { min = 45, max = 49 }, { min = 67, max = 75 } } },
    { id = "still_readable", color = "#E69F00", ranges = { { min = 76, max = 80 } } },
    { id = "too_long",       color = "#D55E00", ranges = { { min = 81 } } },
}

Rating.SHORT = { id = "short", color = nil }

--- The band for a character count. Never returns nil.
function Rating.forChars(n)
    n = math.floor(tonumber(n) or 0)
    for _i, band in ipairs(Rating.BANDS) do
        for _j, range in ipairs(band.ranges) do
            if n >= range.min and (range.max == nil or n <= range.max) then
                return band
            end
        end
    end
    return Rating.SHORT
end

--- "#RRGGBB" to r, g, b (0-255), or nil if the string is not in that form.
function Rating.parseHex(hex)
    if type(hex) ~= "string" then
        return nil
    end
    local r, g, b = hex:match("^#(%x%x)(%x%x)(%x%x)$")
    if not r then
        return nil
    end
    return tonumber(r, 16), tonumber(g, 16), tonumber(b, 16)
end

return Rating
