-- Line-length rating for the Word count plugin. Pure Lua: no KOReader requires.
--
-- The number of characters of a selected line (spaces and symbols included) is mapped to a band.
-- Bands are listed highest first; `min` is the smallest count that belongs to the band. Fewer than
-- 45 characters gets the "short" band, which has no colour (it is shown in the normal text colour).
local Rating = {}

Rating.TIERS = {
    { min = 75, id = "too_long",       color = "#D55E00" },
    { min = 65, id = "still_readable", color = "#E69F00" },
    { min = 55, id = "comfortable",    color = "#009E73" },
    { min = 45, id = "excellent",      color = "#0072B2" },
    { min = 0,  id = "short",          color = nil },
}

--- The band for a character count. Never returns nil.
function Rating.forChars(n)
    n = tonumber(n) or 0
    for i = 1, #Rating.TIERS do
        local tier = Rating.TIERS[i]
        if n >= tier.min then
            return tier
        end
    end
    return Rating.TIERS[#Rating.TIERS]
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
