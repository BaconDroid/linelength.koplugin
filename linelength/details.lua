-- The details card of the Line Length plugin: a small dialog with the characters of the selection or
-- the longest lines of a page, a verdict for the line length, and the four ranges with the current one
-- marked. Built from KOReader's own widgets and modelled on InfoMessage: tap anywhere, or the X in the
-- top right corner, to close it.
-- It takes a report from linelength/report and never touches the selection itself.
local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local InputContainer = require("ui/widget/container/inputcontainer")
local LeftContainer = require("ui/widget/container/leftcontainer")
local LineWidget = require("ui/widget/linewidget")
local OverlapGroup = require("ui/widget/overlapgroup")
local RightContainer = require("ui/widget/container/rightcontainer")
local Size = require("ui/size")
local TextWidget = require("linelength/colortext") -- TextWidget that can keep colour (see that file)
local TitleBar = require("ui/widget/titlebar")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local _ = require("gettext")
local Input = Device.input
local Screen = Device.screen

local Rating = require("linelength/rating")

local Details = InputContainer:extend{
    modal = true,
    report = nil,       -- from linelength/report
    use_color = false,  -- true when the screen is drawing in colour
}

function Details:init()
    if Device:hasKeys() then
        self.key_events.AnyKeyPressed = { { Input.group.Any } }
    end
    if Device:isTouchDevice() then
        self.ges_events.TapClose = {
            GestureRange:new{
                ges = "tap",
                range = Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() },
            },
        }
    end

    local report = self.report
    local border = Size.border.window
    local padding = Screen:scaleBySize(18)
    local card_width = math.floor(Screen:getWidth() * 0.8)
    local width = card_width - 2 * (border + padding) -- width of the content inside the card

    local title_face = Font:getFace("tfont", 24)
    local big_face = Font:getFace("tfont", 72)
    local verdict_face = Font:getFace("tfont", 30)
    local small_face = Font:getFace("x_smallinfofont")
    local row_face = Font:getFace("smallinfofont")
    local row_bold_face = Font:getFace("smallinfofontbold")
    -- the list of longest lines on a page is secondary information: a size smaller than the other rows
    local list_face = Font:getFace("xx_smallinfofont")
    local list_bold_face = Font:getFace("smallinfofontbold", 18)
    local heading_face = Font:getFace("smallinfofontbold", 20)

    -- "#RRGGBB" to a colour, or nil (standard text colour) when the screen is not drawing in colour
    local function color(hex)
        if not (self.use_color and hex) then
            return nil
        end
        local r, g, b = Rating.parseHex(hex)
        if not r then
            return nil
        end
        return Blitbuffer.ColorRGB32(r, g, b, 0xFF)
    end

    local function centered(text, face, fgcolor)
        local widget = TextWidget:new{ text = text, face = face, fgcolor = fgcolor, max_width = width }
        return CenterContainer:new{ dimen = Geom:new{ w = width, h = widget:getSize().h }, widget }
    end

    -- two widgets side by side: one against the left edge, one against the right
    local function sideBySide(left, right)
        local height = math.max(left:getSize().h, right:getSize().h)
        local dimen = Geom:new{ w = width, h = height }
        return OverlapGroup:new{
            dimen = dimen,
            LeftContainer:new{ dimen = Geom:new{ w = width, h = height }, left },
            RightContainer:new{ dimen = Geom:new{ w = width, h = height }, right },
        }
    end

    -- label on the left, value on the right; a long label is cut so it never runs into the value
    local function row(left_text, right_text, left_face, right_face, left_color, right_color)
        local right = TextWidget:new{ text = right_text, face = right_face, fgcolor = right_color }
        local left = TextWidget:new{
            text = left_text, face = left_face, fgcolor = left_color,
            max_width = width - right:getSize().w - Screen:scaleBySize(16),
        }
        return sideBySide(left, right)
    end

    -- One of the longest lines of a page: "L5:" (its number from the top of the page), the start of its
    -- text, and its length on the right. `label_width` is the widest label, so the texts line up.
    local function listRow(line, label_width)
        local gap_width = Screen:scaleBySize(10)
        local label = TextWidget:new{ text = line.number and string.format("L%d:", line.number) or "", face = list_bold_face }
        local right = TextWidget:new{ text = string.format("%d", line.chars), face = list_bold_face }
        local text = TextWidget:new{
            text = line.snippet, face = list_face,
            max_width = width - label_width - gap_width - right:getSize().w - Screen:scaleBySize(16),
        }
        return sideBySide(HorizontalGroup:new{
            align = "center",
            label,
            HorizontalSpan:new{ width = label_width - label:getSize().w + gap_width },
            text,
        }, right)
    end

    local function labelWidth(lines)
        local widest = 0
        for _i, line in ipairs(lines) do
            if line.number then
                local label = TextWidget:new{ text = string.format("L%d:", line.number), face = list_bold_face }
                widest = math.max(widest, label:getSize().w)
                label:free()
            end
        end
        return widest
    end

    local function divider()
        return LineWidget:new{
            background = Blitbuffer.COLOR_GRAY,
            dimen = Geom:new{ w = width, h = Size.line.medium },
        }
    end

    local function gap(size)
        return VerticalSpan:new{ width = Screen:scaleBySize(size) }
    end

    local tier_color = color(report.tier.color)

    local content = VerticalGroup:new{ align = "center" }
    -- the title, a line under it, and the X that closes the card in the top right corner
    self.titlebar = TitleBar:new{
        width = width,
        title = _("Line length"),
        title_face = title_face,
        with_bottom_line = true,
        bottom_line_color = Blitbuffer.COLOR_GRAY,
        close_callback = function() UIManager:close(self) end,
        show_parent = self,
    }
    table.insert(content, self.titlebar)
    table.insert(content, gap(10))
    table.insert(content, centered(string.format("%d", report.chars), big_face, tier_color))
    table.insert(content, centered(report.lines and _("characters in the longest line") or _("characters"), small_face))
    table.insert(content, gap(4))
    table.insert(content, centered(report.tier.label, verdict_face, tier_color))
    table.insert(content, gap(12))
    table.insert(content, divider())
    table.insert(content, gap(8))
    if report.lines then
        -- a whole page: say what the rows are (in bold), then the longest lines, each with its number
        -- on the page and the start of its text
        table.insert(content, centered(#report.lines == 1 and _("Longest line on this page:") or _("Longest lines on this page:"), heading_face))
        table.insert(content, gap(6))
        local label_width = labelWidth(report.lines)
        for _i, line in ipairs(report.lines) do
            table.insert(content, listRow(line, label_width))
        end
    else
        table.insert(content, row(_("With spaces"), string.format("%d", report.chars), row_face, row_bold_face))
        table.insert(content, row(_("Without spaces"), string.format("%d", report.chars_no_spaces), row_face, row_bold_face))
        table.insert(content, row(_("Words"), string.format("%d", report.words), row_face, row_bold_face))
    end
    table.insert(content, gap(8))
    table.insert(content, divider())
    table.insert(content, gap(8))
    for _i, band in ipairs(report.bands) do
        local face = band.current and row_bold_face or row_face
        local band_color = color(band.color)
        table.insert(content, row((band.current and "● " or "○ ") .. band.label, band.range, face, face, band_color, band_color))
    end

    self.frame = FrameContainer:new{
        background = Blitbuffer.COLOR_WHITE,
        radius = Size.radius.window,
        bordersize = border,
        padding = padding,
        margin = 0,
        content,
    }
    self[1] = CenterContainer:new{
        dimen = Screen:getSize(),
        self.frame,
    }

    if self.use_color then
        -- Marks the widget for dithered refreshes, which is what selects a colour waveform on
        -- Kaleido screens (a plain "ui" refresh never shows colour there).
        self.dithered = true
    end
end

function Details:onShow()
    local use_color = self.use_color
    UIManager:setDirty(self, function()
        if use_color then
            return "partial", self.frame.dimen, true
        end
        return "ui", self.frame.dimen
    end)
    return true
end

function Details:onCloseWidget()
    UIManager:setDirty(nil, function()
        return "ui", self.frame.dimen
    end)
end

function Details:onTapClose()
    UIManager:close(self)
    return true
end

function Details:onAnyKeyPressed()
    UIManager:close(self)
    return true
end

return Details
