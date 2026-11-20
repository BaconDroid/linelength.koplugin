-- Line-length rating for the Word count plugin. Pure Lua: no KOReader requires.
--
-- The number of characters of a selected line (spaces and symbols included) is mapped to a band.
-- The edges come from published guidance on "measure" (characters per line); see the README for
-- the sources:
--   50        Baymard: 50 to 75 for body text; Ruder: 50 to 60 is optimal.
--   66        Bringhurst: the 66-character line is ideal.
--   75        Bringhurst and Baymard: the upper end of the satisfactory range.
--   80        WCAG 1.4.8: lines should not exceed 80 characters.
--
-- Excellent runs from where Baymard and Ruder start to Bringhurst's ideal; Comfortable is the rest
-- of the satisfactory range; Still readable is past it but within WCAG's limit; Too long is over
-- that limit. Under 50 is "short" and has no colour: it is shown in the normal text colour.
local Rating = {}

-- In order of quality. `min` and `max` are inclusive; a band without `max` is open-ended.
Rating.BANDS = {
    { id = "excellent",      color = "#0072B2", min = 50, max = 66 },
    { id = "comfortable",    color = "#009E73", min = 67, max = 75 },
    { id = "still_readable", color = "#E69F00", min = 76, max = 80 },
    { id = "too_long",       color = "#D55E00", min = 81 },
}

Rating.SHORT = { id = "short", color = nil }

--- The band for a character count. Never returns nil.
function Rating.forChars(n)
    n = math.floor(tonumber(n) or 0)
    for _i, band in ipairs(Rating.BANDS) do
        if n >= band.min and (band.max == nil or n <= band.max) then
            return band
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
