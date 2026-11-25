-- The auto-tune: how wide the margins have to be for a line to hold the right number of characters.
-- Pure Lua: no KOReader requires, so it is tested on a desktop Lua.
--
-- The size of the text is the reader's own: it is what they read at, and it is not ours to change.
-- The margins are the white space around the text, and they are what the line length is really made
-- of: a wider margin means a narrower block of text, so shorter lines. The auto-tune therefore only
-- moves the margins, and only between the bounds the reader set: the text size is left alone.
--
-- How many characters fit on a line does not depend on the size of the screen: KOReader scales the
-- text size and the margins with the screen, so the same numbers mean the same reading comfort on a
-- small screen as on a large one.
local AutoTune = {}

-- Where the line length should land: a band of good lengths, and the one to aim at inside it.
AutoTune.BAND_MIN = 50
AutoTune.BAND_MAX = 60
AutoTune.TARGET = 60

-- The margins the tune may use.
AutoTune.MARGIN_MIN = 10
AutoTune.MARGIN_MAX = 60

-- How much the margins may move at one step.
-- How many characters the line length may change in one step.
AutoTune.MAX_CHARS_PER_STEP = 6

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
--- long, positive when they are too short. The size of the gap is in characters.
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

--- The margins to try next.
--- The step aims at the band, not at the target: the band is what the loop stops on, so a step that
--- lands inside it ends the loop. Aiming at the target inside the band could jump over it and land on
--- the far side, still outside, and cost another step.
--- @param margin number the margin now, on both sides
--- @param chars number the length of the longest line measured now
--- @param screen_width number the width of the screen in KOReader's units
--- @param limits table|nil margin_min and margin_max; nil uses the defaults
--- @return number|nil the next margin; nil when nothing more can be tried
function AutoTune.nextMargin(margin, chars, screen_width, limits)
    margin = tonumber(margin)
    chars = tonumber(chars)
    local width = tonumber(screen_width)
    if not margin or not chars or not width or chars <= 0 then
        return nil
    end
    limits = limits or {}
    local margin_min = limits.margin_min or AutoTune.MARGIN_MIN
    local margin_max = limits.margin_max or AutoTune.MARGIN_MAX
    local max_chars = limits.max_chars_per_step or AutoTune.MAX_CHARS_PER_STEP

    -- The text block is what the lines are laid out in: how many characters fit on a line is the width
    -- of the block divided by the width of a character. So the length of the lines is proportional to
    -- the width of the block, and the block is the screen minus the margins.
    local text_width = math.max(width - 2 * margin, 1)
    local aim = chars > AutoTune.BAND_MAX and AutoTune.BAND_MAX or AutoTune.BAND_MIN
    local wanted_width = text_width * aim / chars
    local wanted_margin = (width - wanted_width) / 2

    -- The step goes where the measurement points, but it never moves the line length by more than a
    -- few characters at a time: a step that jumped over the band would land outside it again and
    -- cost another measurement. The bounds the reader set have the last word.
    local step_width = text_width * max_chars / chars
    local step_margin = math.abs(wanted_margin - margin) <= step_width / 2 and wanted_margin
        or (wanted_margin > margin and margin + step_width / 2 or margin - step_width / 2)
    local new_margin = math.floor(step_margin + 0.5)
    new_margin = math.max(margin_min, math.min(margin_max, new_margin))
    if new_margin == margin then
        return nil
    end
    return new_margin
end

--- The margin the auto-tune starts from: the one the book is laid out with, pulled inside the bounds.
--- @param margin number the margin now
--- @param limits table|nil margin_min and margin_max; nil uses the defaults
--- @return number
function AutoTune.startMargin(margin, limits)
    limits = limits or {}
    local margin_min = limits.margin_min or AutoTune.MARGIN_MIN
    local margin_max = limits.margin_max or AutoTune.MARGIN_MAX
    margin = tonumber(margin) or margin_min
    margin = math.floor(margin + 0.5)
    return math.max(margin_min, math.min(margin_max, margin))
end

return AutoTune
