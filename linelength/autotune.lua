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
AutoTune.BAND_MIN = 56
AutoTune.BAND_MAX = 60
AutoTune.TARGET = 58

-- The margins the tune may use.
AutoTune.MARGIN_MIN = 20
AutoTune.MARGIN_MAX = 50

-- How many characters the line length may change in one step.
AutoTune.MAX_CHARS_PER_STEP = 6

-- The range the settings are held to, as the menu offers them: a value outside is brought back to the
-- edge of its range rather than obeyed. A band of nothing and a margin of nothing are not a line and
-- not a margin, so the band has a floor of its own and the margins have theirs.
AutoTune.BAND_FLOOR = 10
AutoTune.BAND_CEILING = 200
AutoTune.MARGIN_FLOOR = 0
AutoTune.MARGIN_CEILING = 200
AutoTune.STEP_FLOOR = 1
AutoTune.STEP_CEILING = 30

-- A number from the settings, kept inside the range the menu offers. The settings file is a plain
-- Lua table a reader can edit, so a value outside the range is not a reason to stop: it is brought
-- back to the end of the range it belongs to, and a value that is not a number falls back to the
-- default.
local function within(value, default, min, max)
    local n = tonumber(value)
    if not n then
        return default
    end
    return math.max(min, math.min(max, n))
end

--- The limits of the tune, from the settings the reader chose: the band of line lengths, the target
--- inside it, the bounds of the margins and the size of a step, checked against each other so that
--- the loop always has something to aim for.
--- @param settings table|nil the settings, as in linelength/settings.lua
--- @return table { band_min, band_max, target, margin_min, margin_max, max_chars_per_step }
function AutoTune.limits(settings)
    settings = settings or {}
    local band_min = within(settings.band_min, AutoTune.BAND_MIN, AutoTune.BAND_FLOOR, AutoTune.BAND_CEILING)
    local band_max = within(settings.band_max, AutoTune.BAND_MAX, AutoTune.BAND_FLOOR, AutoTune.BAND_CEILING)
    -- A margin is the white space around the text, so it has a floor of its own: a negative one is not
    -- a margin at all, and KOReader would put a meaningless width on the page.
    local margin_min = within(settings.margin_min, AutoTune.MARGIN_MIN, AutoTune.MARGIN_FLOOR, AutoTune.MARGIN_CEILING)
    local margin_max = within(settings.margin_max, AutoTune.MARGIN_MAX, AutoTune.MARGIN_FLOOR, AutoTune.MARGIN_CEILING)
    -- The reader can leave a pair the wrong way round in the settings file: the shortest line cannot
    -- be longer than the longest one, so the pair is put the right way round here.
    if band_min > band_max then
        band_min, band_max = band_max, band_min
    end
    if margin_min > margin_max then
        margin_min, margin_max = margin_max, margin_min
    end
    -- A step of nothing would leave the loop turning the same margin over and over, so the smallest
    -- step is one character.
    local target = within(settings.target, AutoTune.TARGET, AutoTune.BAND_FLOOR, AutoTune.BAND_CEILING)
    return {
        band_min = band_min,
        band_max = band_max,
        -- The target is the length the loop aims at, and the band is what it stops on: a target
        -- outside the band is brought to the edge rather than left to pull the loop past it.
        target = math.max(band_min, math.min(band_max, target)),
        margin_min = margin_min,
        margin_max = margin_max,
        max_chars_per_step = within(settings.max_chars_per_step, AutoTune.MAX_CHARS_PER_STEP,
            AutoTune.STEP_FLOOR, AutoTune.STEP_CEILING),
    }
end

--- Whether a line length is good enough: inside the band.
--- @param chars number the length of the longest line, in characters
--- @param limits table|nil the limits, as AutoTune.limits returns them; nil uses the defaults
--- @return boolean
function AutoTune.inBand(chars, limits)
    chars = tonumber(chars)
    if not chars then
        return false
    end
    limits = limits or {}
    local band_min = limits.band_min or AutoTune.BAND_MIN
    local band_max = limits.band_max or AutoTune.BAND_MAX
    return chars >= band_min and chars <= band_max
end

--- How far the measured length is from the band: 0 when it is inside it, negative when the lines are too
--- long, positive when they are too short. The size of the gap is in characters.
--- @param chars number the length of the longest line, in characters
--- @param limits table|nil the limits, as AutoTune.limits returns them; nil uses the defaults
--- @return number
function AutoTune.distance(chars, limits)
    chars = tonumber(chars) or 0
    limits = limits or {}
    local band_min = limits.band_min or AutoTune.BAND_MIN
    local band_max = limits.band_max or AutoTune.BAND_MAX
    if chars < band_min then
        return band_min - chars
    end
    if chars > band_max then
        return band_max - chars
    end
    return 0
end

--- The margins to try next.
--- The step aims at the target the reader asked for, the length of line they want to read at. It never
--- moves the line length by more than a few characters at a time: a step that jumped over the band
--- would land outside it again and cost another measurement. The target is kept inside the band,
--- because the band is what the loop stops on: a target outside it would send the loop past the band.
--- @param margin number the margin now, on both sides
--- @param chars number the length of the longest line measured now
--- @param screen_width number the width of the screen in KOReader's units
--- @param limits table|nil the limits, as AutoTune.limits returns them; nil uses the defaults
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
    local band_min = limits.band_min or AutoTune.BAND_MIN
    local band_max = limits.band_max or AutoTune.BAND_MAX
    local target = tonumber(limits.target) or AutoTune.TARGET

    -- The text block is what the lines are laid out in: how many characters fit on a line is the width
    -- of the block divided by the width of a character. So the length of the lines is proportional to
    -- the width of the block, and the block is the screen minus the margins.
    local text_width = math.max(width - 2 * margin, 1)

    -- The aim: the target the reader asked for, inside the band the reader asked for.
    local aim = math.min(math.max(target, band_min), band_max)

    -- The step, in characters: the distance to the aim, capped at the step size the reader set.
    local step = aim - chars
    if step > max_chars then
        step = max_chars
    elseif step < -max_chars then
        step = -max_chars
    end

    -- The margin that gives the text block the wanted number of characters.
    local next_margin = (width - text_width * (chars + step) / chars) / 2
    local new_margin = math.floor(next_margin + 0.5)

    -- A margin outside the bounds comes back inside them first: the bounds are what the reader asked
    -- for, and a step that stayed outside would measure the same thing again.
    if margin < margin_min then
        new_margin = margin_min
    elseif margin > margin_max then
        new_margin = margin_max
    else
        new_margin = math.max(margin_min, math.min(margin_max, new_margin))
    end
    if new_margin == margin then
        return nil
    end
    return new_margin
end

--- The margin the auto-tune starts from: the one the book is laid out with, pulled inside the bounds.
--- @param margin number the margin now
--- @param limits table|nil the limits, as AutoTune.limits returns them; nil uses the defaults
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
