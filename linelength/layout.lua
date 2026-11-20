-- Steps for the margins and the text size of a book, for the buttons on the page card. Pure Lua: no KOReader
-- requires, so it is tested on a desktop.
--
-- Units: KOReader keeps margins and font size "unscaled", the numbers its own menus show (a margin of 10, a font
-- size of 22), and multiplies them by a screen factor when it lays out the page. Every number here is one of
-- those unscaled ones, including the width of the screen.
local Layout = {}

-- One tap changes the width of the text by about this fraction: about 3 characters on a line of 60. Smaller steps
-- are not seen: lines break at whole words, so the longest line only moves when the width moves by a few percent.
Layout.STEP = 0.05
-- KOReader's own limits: each of the left and right margin goes from 0 to 140, the font size from 12 to 255.
Layout.MARGIN_MIN, Layout.MARGIN_MAX = 0, 140
Layout.FONT_MIN, Layout.FONT_MAX = 12, 255

local function round(x)
    return math.floor(x + 0.5)
end

local function isNumber(x)
    return type(x) == "number" and x == x and x ~= math.huge and x ~= -math.huge
end

--- The margins after one step.
--- @param margins table { left, right }
--- @param direction number 1 = wider margins (shorter lines), -1 = narrower margins (longer lines)
--- @param screen_width number the width of the screen
--- @return table|nil the new { left, right }; nil when nothing can change (at a limit) or the input is unusable
function Layout.stepMargins(margins, direction, screen_width)
    if type(margins) ~= "table" or not isNumber(margins[1]) or not isNumber(margins[2]) or not isNumber(screen_width) then
        return nil
    end
    if direction ~= 1 and direction ~= -1 then
        return nil
    end
    local text_width = math.max(screen_width - margins[1] - margins[2], 0)
    -- each side takes half of the change, so the text keeps its place when the margins differ
    local each_side = math.max(1, round(Layout.STEP / 2 * text_width))
    local function step(value)
        -- never moves against the direction, even when the value is already outside KOReader's range
        if direction > 0 then
            return math.max(value, math.min(Layout.MARGIN_MAX, value + each_side))
        end
        return math.min(value, math.max(Layout.MARGIN_MIN, value - each_side))
    end
    local left, right = step(margins[1]), step(margins[2])
    if left == margins[1] and right == margins[2] then
        return nil
    end
    return { left, right }
end

--- The font size after one step.
--- @param size number the font size
--- @param direction number 1 = bigger text (shorter lines), -1 = smaller text (longer lines)
--- @return number|nil the new size; nil when it cannot change (at a limit) or the input is unusable
function Layout.stepFontSize(size, direction)
    if not isNumber(size) or (direction ~= 1 and direction ~= -1) then
        return nil
    end
    local amount = math.max(1, round(size * Layout.STEP))
    local new
    if direction > 0 then
        new = math.max(size, math.min(Layout.FONT_MAX, size + amount))
    else
        new = math.min(size, math.max(Layout.FONT_MIN, size - amount))
    end
    if new == size then
        return nil
    end
    return new
end

--- A margin or a size as shown between the "−" and the "+" of a stepper: 10, 22, 22.5 (no trailing zeros).
--- @param value number
--- @return string
function Layout.formatNumber(value)
    if not isNumber(value) then
        return ""
    end
    return string.format("%g", value)
end

--- The margins as the stepper shows them: "10" when both sides are the same, "10/14" when they are not.
--- @param margins table { left, right }
--- @return string
function Layout.formatMargins(margins)
    if type(margins) ~= "table" then
        return ""
    end
    local left, right = Layout.formatNumber(margins[1]), Layout.formatNumber(margins[2])
    if left == "" or right == "" then
        return ""
    end
    if left == right then
        return left
    end
    return left .. "/" .. right
end

--- Which buttons can be used now.
--- @param layout table { margins = { left, right }, size = number }
--- @param screen_width number
--- @return table { margins_less, margins_more, text_less, text_more } booleans
function Layout.controls(layout, screen_width)
    layout = layout or {}
    return {
        margins_less = Layout.stepMargins(layout.margins, -1, screen_width) ~= nil,
        margins_more = Layout.stepMargins(layout.margins, 1, screen_width) ~= nil,
        text_less = Layout.stepFontSize(layout.size, -1) ~= nil,
        text_more = Layout.stepFontSize(layout.size, 1) ~= nil,
    }
end

return Layout
