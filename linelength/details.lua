-- The details card of the Line Length plugin: a small dialog with the characters of the selection or
-- the longest lines of a page, a verdict for the line length, and the four ranges with the current one
-- marked. Built from KOReader's own widgets and modelled on InfoMessage: tap anywhere, or the X in the
-- top right corner, to close it.
--
-- The card of a page can also carry the controls that fix a line length that is too long: a stepper for the
-- margins and one for the text size (a "−" and a "+" around the current value), and two buttons at the bottom.
-- `controls` says which of the four steppers' buttons are usable, `values` the numbers shown between the "−" and the
-- "+", `on_control(id)` is called when a button is tapped, and `update` redraws the card with a new report.
-- With the controls on it, a tap closes the card only outside of it, like KOReader's own dialogs, so a tap that
-- misses a button does not lose the page.
--
-- Two sizes. The full card has the whole report, and at the bottom Cancel (put everything back as it was when the card
-- opened, and close) and Done (keep what was changed, and close). A tap on one of the steppers shrinks the card to what
-- is needed to watch the effect (the title, the number, the verdict and the controls), so the page behind it shows, and
-- it stays small until the user decides: Cancel (put everything back and go back to the full card) or Accept (keep
-- what was changed and go back to the full card). The bottom edge of the card does not move when it shrinks, so every
-- button stays where the finger was.
-- It takes a report from linelength/report and never touches the selection itself.
local Blitbuffer = require("ffi/blitbuffer")
local BottomContainer = require("ui/widget/container/bottomcontainer")
local Button = require("ui/widget/button")
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

-- The two steppers. A "+" makes the lines shorter (more margin, bigger text), a "−" makes them longer.
local STEPPERS = {
    { label = _("Margins"), value = "margins", less = "margins_less", more = "margins_more" },
    { label = _("Text size"), value = "size", less = "text_less", more = "text_more" },
}

-- The space (in KOReader units) between the Text size stepper and the buttons at the bottom. One value for both sizes
-- of the card, so the two look the same.
local ACTIONS_GAP = 16

-- How much of the width of the screen the card takes: a bit more in landscape, where it has two columns.
local PORTRAIT_WIDTH, LANDSCAPE_WIDTH = 0.8, 0.9

-- The buttons that change the layout: a tap on one of them shrinks the card.
local STEPS = { margins_less = true, margins_more = true, text_less = true, text_more = true }

local Details = InputContainer:extend{
    modal = true,
    report = nil,       -- from linelength/report
    use_color = false,  -- true when the screen is drawing in colour
    controls = nil,     -- { margins_less, margins_more, text_less, text_more = usable? }; nil: no buttons
    values = nil,       -- { margins = "10", size = "22" }: what the steppers show
    on_control = nil,   -- function(id) called when a button is tapped
    compact = false,    -- true while the card is shrunk
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
    self:build()
end

-- (Re)builds everything that is drawn from self.report, self.controls, self.values and self.compact.
function Details:build()
    if self[1] and self[1].free then
        self[1]:free()
    end
    local report = self.report
    local compact = self.compact and self.controls ~= nil
    local border = Size.border.window
    local padding = Screen:scaleBySize(18)
    -- On a screen that is wider than tall the card is wider too and its content goes in two columns, so that the card is
    -- wider than tall itself and fits on the screen (in one column it is taller than a landscape screen).
    local landscape = Screen:getWidth() > Screen:getHeight()
    local card_width = math.floor(Screen:getWidth() * (landscape and LANDSCAPE_WIDTH or PORTRAIT_WIDTH))
    local width = card_width - 2 * (border + padding) -- width of the content inside the card
    local column_gap = Screen:scaleBySize(28)
    local column_width = math.floor((width - column_gap) / 2)

    local title_face = Font:getFace("tfont", 24)
    local big_face = Font:getFace("tfont", 60)
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

    local function centered(text, face, fgcolor, w)
        w = w or width
        local widget = TextWidget:new{ text = text, face = face, fgcolor = fgcolor, max_width = w }
        return CenterContainer:new{ dimen = Geom:new{ w = w, h = widget:getSize().h }, widget }
    end

    -- two widgets side by side: one against the left edge, one against the right
    local function sideBySide(left, right, w)
        w = w or width
        local height = math.max(left:getSize().h, right:getSize().h)
        local dimen = Geom:new{ w = w, h = height }
        return OverlapGroup:new{
            dimen = dimen,
            LeftContainer:new{ dimen = Geom:new{ w = w, h = height }, left },
            RightContainer:new{ dimen = Geom:new{ w = w, h = height }, right },
        }
    end

    -- label on the left, value on the right; a long label is cut so it never runs into the value
    local function row(left_text, right_text, left_face, right_face, left_color, right_color, w)
        w = w or width
        local right = TextWidget:new{ text = right_text, face = right_face, fgcolor = right_color }
        local left = TextWidget:new{
            text = left_text, face = left_face, fgcolor = left_color,
            max_width = w - right:getSize().w - Screen:scaleBySize(16),
        }
        return sideBySide(left, right, w)
    end

    -- One of the longest lines of a page: "L5:" (its number from the top of the page), the start of its
    -- text, and its length on the right. `label_width` is the widest label, so the texts line up.
    local function listRow(line, label_width, w)
        w = w or width
        local gap_width = Screen:scaleBySize(10)
        local label = TextWidget:new{ text = line.number and string.format("L%d:", line.number) or "", face = list_bold_face }
        local right = TextWidget:new{ text = string.format("%d", line.chars), face = list_bold_face }
        local text = TextWidget:new{
            text = line.snippet, face = list_face,
            max_width = w - label_width - gap_width - right:getSize().w - Screen:scaleBySize(16),
        }
        return sideBySide(HorizontalGroup:new{
            align = "center",
            label,
            HorizontalSpan:new{ width = label_width - label:getSize().w + gap_width },
            text,
        }, right, w)
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

    local function divider(w)
        return LineWidget:new{
            background = Blitbuffer.COLOR_GRAY,
            dimen = Geom:new{ w = w or width, h = Size.line.medium },
        }
    end

    local function gap(size)
        return VerticalSpan:new{ width = Screen:scaleBySize(size) }
    end

    -- A real, bordered button. Anything that cannot be used now is drawn grey, the way KOReader draws it.
    self.buttons = {}
    local function button(id, text, button_width, button_height, opts)
        opts = opts or {}
        local made = Button:new{
            text = text,
            text_font_size = opts.font_size or 22,
            text_font_bold = opts.bold == true,
            width = button_width,
            height = button_height,
            radius = Size.radius.button,
            bordersize = opts.bordersize or Size.border.button,
            margin = 0,
            padding = 0,
            enabled = opts.always or self.controls[id] == true,
            callback = function() self:press(id) end,
            show_parent = self,
        }
        self.buttons[id] = made
        return made
    end

    -- "Margins        [ − ]  10  [ + ]": the label on the left, the stepper on the right
    local function stepper(step, w)
        local step_height = Screen:scaleBySize(48) -- Material's 48dp, Apple's 44pt: a finger-sized target
        local button_width = Screen:scaleBySize(62)
        local value_width = Screen:scaleBySize(64)
        local value = TextWidget:new{ text = self.values and self.values[step.value] or "", face = row_bold_face }
        local group = HorizontalGroup:new{
            align = "center",
            button(step.less, "−", button_width, step_height, { font_size = 28, bold = true }),
            CenterContainer:new{ dimen = Geom:new{ w = value_width, h = step_height }, value },
            button(step.more, "+", button_width, step_height, { font_size = 28, bold = true }),
        }
        return sideBySide(TextWidget:new{ text = step.label, face = row_bold_face }, group, w)
    end

    -- Cancel on the left and the confirming action on the right, as in KOReader's dialogs. Full size: Done closes the
    -- card; shrunk: Accept goes back to the full card. They are in the same places in both sizes.
    local function actions()
        local gap_width = Screen:scaleBySize(10)
        local button_width = math.floor((width - gap_width) / 2)
        local button_height = Screen:scaleBySize(48)
        local confirm = compact and button("accept", _("Accept"), button_width, button_height, { always = true, bordersize = Size.border.thick })
            or button("done", _("Done"), button_width, button_height, { always = true, bordersize = Size.border.thick })
        return HorizontalGroup:new{
            button("cancel", _("Cancel"), button_width, button_height, { always = true }),
            HorizontalSpan:new{ width = gap_width },
            confirm,
        }
    end

    local tier_color = color(report.tier.color)

    -- The parts the card is made of, each for the width it is laid out in (the whole content, or one column).
    local function append(list, items)
        for _i, item in ipairs(items) do
            table.insert(list, item)
        end
    end
    -- the number, what it counts and the verdict
    local function scoreBlock(w)
        return {
            centered(string.format("%d", report.chars), big_face, tier_color, w),
            centered(report.lines and _("characters in the longest line") or _("characters"), small_face, nil, w),
            gap(4),
            centered(report.tier.label, verdict_face, tier_color, w),
        }
    end
    -- the longest lines of a whole page (say what the rows are, in bold, then each line with its number on the page and
    -- the start of its text), or the counts of a selection
    local function detailsBlock(w)
        local items = {}
        if report.lines then
            table.insert(items, centered(#report.lines == 1 and _("Longest line on this page:") or _("Longest lines on this page:"), heading_face, nil, w))
            table.insert(items, gap(4))
            local label_width = labelWidth(report.lines)
            for _i, line in ipairs(report.lines) do
                table.insert(items, listRow(line, label_width, w))
            end
        else
            table.insert(items, row(_("With spaces"), string.format("%d", report.chars), row_face, row_bold_face, nil, nil, w))
            table.insert(items, row(_("Without spaces"), string.format("%d", report.chars_no_spaces), row_face, row_bold_face, nil, nil, w))
            table.insert(items, row(_("Words"), string.format("%d", report.words), row_face, row_bold_face, nil, nil, w))
        end
        return items
    end
    -- the ranges, the one the page is in marked
    local function bandsBlock(w)
        local items = {}
        for _i, band in ipairs(report.bands) do
            local face = band.current and row_bold_face or row_face
            local band_color = color(band.color)
            table.insert(items, row((band.current and "● " or "○ ") .. band.label, band.range, face, face, band_color, band_color, w))
        end
        return items
    end
    -- the steppers that change the margins and the text size
    local function steppersBlock(w)
        local items = {}
        for index, step in ipairs(STEPPERS) do
            if index > 1 then
                table.insert(items, gap(5))
            end
            table.insert(items, stepper(step, w))
        end
        return items
    end
    local function stack(items)
        local group = VerticalGroup:new{ align = "center" }
        append(group, items)
        return group
    end

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
    table.insert(content, gap(6))

    if not landscape then
        -- one column
        append(content, scoreBlock())
        table.insert(content, gap(6))
        table.insert(content, divider())
        table.insert(content, gap(5))
        if not compact then
            append(content, detailsBlock())
            table.insert(content, gap(5))
            table.insert(content, divider())
            table.insert(content, gap(5))
            append(content, bandsBlock())
        end
        -- the controls that change the margins and the text size, when the card has them
        if self.controls then
            if not compact then
                table.insert(content, gap(5))
                table.insert(content, divider())
            end
            table.insert(content, gap(6))
            append(content, steppersBlock())
            table.insert(content, gap(ACTIONS_GAP))
            table.insert(content, actions())
        end
    else
        -- two columns. With the controls: the score and the ranges on the left, the longest lines and the steppers on the
        -- right. Without them: the score on the left, everything else on the right.
        local left, right = {}, {}
        local flex -- where the right column takes up spare height: above the steppers, so that they stay at the bottom
        append(left, scoreBlock(column_width))
        if self.controls then
            if not compact then
                append(left, { gap(6), divider(column_width), gap(5) })
                append(left, bandsBlock(column_width))
                append(right, detailsBlock(column_width))
                append(right, { gap(5), divider(column_width) })
            end
            flex = #right + 1
            table.insert(right, gap(6))
            append(right, steppersBlock(column_width))
        else
            append(right, detailsBlock(column_width))
            append(right, { gap(5), divider(column_width), gap(5) })
            append(right, bandsBlock(column_width))
        end
        -- the columns are the same height, so the steppers (and everything above the buttons) are at the same place
        -- whether the card is full or shrunk
        local left_height, right_height = stack(left):getSize().h, stack(right):getSize().h
        if left_height < right_height then
            local spare = right_height - left_height
            if self.controls then
                table.insert(left, VerticalSpan:new{ width = spare })
            else
                -- the score alone is centred against the other column
                table.insert(left, 1, VerticalSpan:new{ width = math.floor(spare / 2) })
                table.insert(left, VerticalSpan:new{ width = spare - math.floor(spare / 2) })
            end
        elseif right_height < left_height then
            table.insert(right, flex or (#right + 1), VerticalSpan:new{ width = left_height - right_height })
        end
        table.insert(content, HorizontalGroup:new{
            align = "top",
            stack(left),
            HorizontalSpan:new{ width = column_gap },
            stack(right),
        })
        if self.controls then
            table.insert(content, gap(ACTIONS_GAP))
            table.insert(content, actions())
        end
    end

    self.frame = FrameContainer:new{
        background = Blitbuffer.COLOR_WHITE,
        radius = Size.radius.window,
        bordersize = border,
        padding = padding,
        margin = 0,
        content,
    }
    if compact then
        -- Shrunk: the bottom edge stays where the full card had it, so every button stays where it was.
        self[1] = BottomContainer:new{
            dimen = Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = self.anchor_bottom or Screen:getHeight() },
            self.frame,
        }
    else
        self.anchor_bottom = math.floor((Screen:getHeight() + self.frame:getSize().h) / 2)
        self[1] = CenterContainer:new{
            dimen = Screen:getSize(),
            self.frame,
        }
    end

    if self.use_color then
        -- Marks the widget for dithered refreshes, which is what selects a colour waveform on
        -- Kaleido screens (a plain "ui" refresh never shows colour there).
        self.dithered = true
    end
end

-- A button was tapped.
-- Done closes the card and keeps what was changed. Accept (on the shrunk card) keeps it and shows the full card; the
-- plugin is asked to measure the page again first, so the full card shows what the page holds now (the numbers on
-- the shrunk card can be one change behind while KOReader is still rendering). Cancel asks the plugin to put everything back: on the full card the card then closes; on the shrunk card the plugin
-- measures the page again and redraws it, and it is full size again (the plugin is asked to "revert", not "cancel",
-- because the card stays). A button that changes the layout shrinks the card, when the plugin redraws it with the new
-- numbers. Nothing here waits for anything: the card stays shrunk until Cancel or Accept.
function Details:press(id)
    if id == "done" then
        UIManager:close(self)
        return
    end
    if id == "accept" then
        -- nothing changes in the book on Accept, so the page behind the card stays as it is: only the card is refreshed
        self.expand_on_update, self.card_only_refresh = true, true
        local ok, err = true, nil
        if self.on_control then
            ok, err = pcall(self.on_control, "accept")
        end
        self.expand_on_update, self.card_only_refresh = false, false
        self:expand() -- also when the plugin could not measure: Accept always shows the full card
        if not ok then
            error(err, 0)
        end
        return
    end
    local shrinks = STEPS[id] == true and self.controls ~= nil
    local reverts = id == "cancel" and self.compact
    self.shrink_on_update, self.expand_on_update = shrinks, reverts
    local ok, err = true, nil
    if self.on_control then
        ok, err = pcall(self.on_control, reverts and "revert" or id)
    end
    self.shrink_on_update, self.expand_on_update = false, false
    if not ok then
        error(err, 0)
    end
    if id == "cancel" and not reverts then
        UIManager:close(self)
    end
end

-- Full size, with whatever the card shows now.
function Details:expand()
    if not self.compact then
        return
    end
    self.compact = false
    self:build()
    self:refresh(true) -- only called when nothing changed in the book (Accept): the page behind the card is as it was
end

-- Asks the screen to redraw: the whole screen when the page behind the card has changed too (a step, a Cancel on the
-- shrunk card), or only the card when it has not (Accept). A refresh of the panel is what blinks on a colour
-- Kobo, and the area that blinks is the area that is refreshed. The region is read when the refresh is made, after the
-- card has been painted (that is where the frame knows its place); without one the whole screen is refreshed.
function Details:refresh(card_only)
    local use_color = self.use_color
    UIManager:setDirty("all", function()
        local region = card_only and self.frame and self.frame.dimen or nil
        if use_color then
            return "partial", region, true
        end
        return "ui", region
    end)
end

-- Redraws the card for a new report (and, when given, new states of the buttons and new values), for example
-- after the page was laid out again. If a button that changes the layout was just tapped, the card is shrunk; if
-- Cancel was just tapped on the shrunk card, it is full size again.
function Details:update(report, controls, values)
    self.report = report
    if controls ~= nil then
        self.controls = controls
    end
    if values ~= nil then
        self.values = values
    end
    if self.shrink_on_update then
        self.compact = true
    elseif self.expand_on_update then
        self.compact = false
    end
    self:build()
    self:refresh(self.card_only_refresh)
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

function Details:onTapClose(_arg, ges)
    -- With buttons on the card, only a tap outside of it closes it (the way KOReader's own dialogs behave).
    if self.controls and ges and ges.pos then
        local dimen = self.frame.dimen
        if not dimen or not ges.pos:notIntersectWith(dimen) then
            return true -- inside the card, or the card is not on the screen yet
        end
    end
    UIManager:close(self)
    return true
end

function Details:onAnyKeyPressed()
    UIManager:close(self)
    return true
end

return Details
