-- The auto-tune: what to do with the margins and the text size to get the line length where it should
-- be. Pure Lua: no KOReader requires, so it is tested on a desktop Lua.
--
-- The line length of a book is set by the text size and the width of the text block, which is the width
-- of the screen minus the margins. Making the text bigger or the margins wider shortens the lines; both
-- do the same thing, but the margins are the less intrusive of the two: the size of the text is what the
-- reader reads at, and it is not ours to change without need. So the margins move first, and the text
-- size only when the margins cannot go any further.
local AutoTune = {}

-- Where the line length should land: a band of good lengths, and the one to aim at inside it.
AutoTune.BAND_MIN = 50
AutoTune.BAND_MAX = 66
AutoTune.TARGET = 60

-- How far the text size and the margins may go.
AutoTune.FONT_MIN = 20
AutoTune.FONT_MAX = 27
AutoTune.MARGIN_MIN = 10
AutoTune.MARGIN_MAX = 60

--- Whether a line length is good enough: inside the band.
--- @param chars number the length of the longest line, in characters
--- @return boolean
function AutoTune.inBand(chars)
    chars = tonumber(chars)
    if not chars then
        return false
    end
    return chars >= AutoTune.BAND_MIN and chars <= AutoTune.BAND_MAX
end

--- How far the measured length is from the band: 0 when it is inside it, negative when the lines are too
--- long, positive when they are too short. The size of the gap is in characters, so it can be compared
--- with what a step of the margins buys.
--- @param chars number the length of the longest line, in characters
--- @return number
function AutoTune.distance(chars)
    chars = tonumber(chars) or 0
    if chars < AutoTune.BAND_MIN then
        return AutoTune.BAND_MIN - chars
    end
    if chars > AutoTune.BAND_MAX then
        return AutoTune.BAND_MAX - chars
    end
    return 0
end

--- The margins and the text size to try next. The margins move first: they leave the size of the text
--- alone, and the text size only moves when the margins have reached their limit and the lines are
--- still too long.
--- @param layout table the layout now, with margins (a pair) and size
--- @param chars number the length of the longest line measured now
--- @param screen_width number the width of the screen in KOReader's units
--- @param limits table|nil font and margin limits; nil uses the defaults
--- @return table|nil the next layout, with margins (a pair) and size; nil when nothing more can be tried
function AutoTune.next(layout, chars, screen_width, limits)
    if type(layout) ~= "table" or type(layout.margins) ~= "table" then
        return nil
    end
    local left, right = tonumber(layout.margins[1]), tonumber(layout.margins[2])
    local size = tonumber(layout.size)
    local width = tonumber(screen_width)
    if not left or not right or not size or not width then
        return nil
    end
    limits = limits or {}
    local font_min = limits.font_min or AutoTune.FONT_MIN
    local font_max = limits.font_max or AutoTune.FONT_MAX
    local margin_min = limits.margin_min or AutoTune.MARGIN_MIN
    local margin_max = limits.margin_max or AutoTune.MARGIN_MAX

    chars = tonumber(chars) or 0
    if chars <= 0 then
        return nil
    end
    local too_long = chars > AutoTune.BAND_MAX

    -- The text block is what the lines are laid out in: how many characters fit on a line is the width
    -- of the block divided by the width of a character, and the width of a character grows with the
    -- text size. So the length of the lines is proportional to the width of the block for a given text
    -- size, and inversely proportional to the text size for a given block.
    --
    -- The step aims at the band, not at the target: the band is what the loop stops on, so a step that
    -- lands inside it ends the loop. Aiming at the target inside the band could jump over it and land
    -- on the far side, still outside, and cost another step.
    local text_width = math.max(width - left - right, 1)
    local aim = too_long and AutoTune.BAND_MAX or AutoTune.BAND_MIN
    local wanted_width = math.floor(text_width * aim / chars + 0.5)
    local wanted_margin = math.floor((width - wanted_width) / 2 + 0.5)
    local wanted_size = math.floor(size * chars / aim + 0.5)

    local function clamp_margin(value)
        return math.max(margin_min, math.min(margin_max, value))
    end
    local function clamp_font(value)
        return math.max(font_min, math.min(font_max, value))
    end

    if too_long then
        local new_margin = clamp_margin(wanted_margin)
        if new_margin > left or new_margin > right then
            return { margins = { new_margin, new_margin }, size = size }
        end
        local new_size = clamp_font(wanted_size)
        if new_size > size then
            return { margins = { left, right }, size = new_size }
        end
        return nil
    end

    local new_margin = clamp_margin(wanted_margin)
    if new_margin < left or new_margin < right then
        return { margins = { new_margin, new_margin }, size = size }
    end
    local new_size = clamp_font(wanted_size)
    if new_size < size then
        return { margins = { left, right }, size = new_size }
    end
    return nil
end

--- The layout the auto-tune starts from: the size of the text the reader is used to, and the margins
--- the book is laid out with, unless they are outside the limits.
--- @param layout table the layout now, with margins (a pair) and size
--- @param limits table|nil font and margin limits; nil uses the defaults
--- @return table a layout, with margins (a pair) and size
function AutoTune.start(layout, limits)
    limits = limits or {}
    local margin_min = limits.margin_min or AutoTune.MARGIN_MIN
    local margin_max = limits.margin_max or AutoTune.MARGIN_MAX
    local font_min = limits.font_min or AutoTune.FONT_MIN
    local font_max = limits.font_max or AutoTune.FONT_MAX
    local left = layout.margins[1]
    local right = layout.margins[2]
    local size = layout.size
    left = math.max(margin_min, math.min(margin_max, math.floor(left + 0.5)))
    right = math.max(margin_min, math.min(margin_max, math.floor(right + 0.5)))
    size = math.max(font_min, math.min(font_max, math.floor(size + 0.5)))
    return { margins = { left, right }, size = size }
end

return AutoTune
