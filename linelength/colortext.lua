-- Coloured text for the details card.
--
-- KOReader's TextWidget draws glyphs with BlitBuffer:colorblitFrom, which starts with
-- color:getColor8A(): it keeps only the brightness of the colour, so whatever fgcolor is set, the
-- text comes out grey. BlitBuffer also has colorblitFromRGB32, which keeps the colour, but
-- TextWidget never calls it. This widget is TextWidget with one difference: when fgcolor is a real
-- colour (not a grey) and the buffer supports it, the same glyphs are drawn with colorblitFromRGB32.
-- In every other case it defers to TextWidget, so greys and old KOReader versions behave as before.
local Blitbuffer = require("ffi/blitbuffer")
local RenderText = require("ui/rendertext")
local TextWidget = require("ui/widget/textwidget")

local ColorTextWidget = TextWidget:extend{}

function ColorTextWidget:paintTo(bb, x, y)
    local color = self.fgcolor
    if color and not Blitbuffer.isColor8(color) and bb.colorblitFromRGB32 then
        self:updateSize()
        if self._is_empty then
            return
        end
        if self.use_xtext then
            -- the same loop as TextWidget:paintTo, with the colour-keeping blit
            if not self._xshaping then
                self._xshaping = self._xtext:shapeLine(self._shape_start, self._shape_end,
                    self._shape_idx_to_substitute_with_ellipsis)
            end
            local text_width = bb:getWidth() - x
            if self.max_width and self.max_width < text_width then
                text_width = self.max_width
            end
            local pen_x = 0
            local baseline = self.forced_baseline or self._baseline_h
            for _i, xglyph in ipairs(self._xshaping) do
                if pen_x >= text_width then
                    break
                end
                local face = self.face.getFallbackFont(xglyph.font_num)
                local glyph = RenderText:getGlyphByIndex(face, xglyph.glyph, self.bold)
                bb:colorblitFromRGB32(
                    glyph.bb,
                    x + pen_x + glyph.l + xglyph.x_offset,
                    y + baseline - glyph.t - xglyph.y_offset,
                    0, 0,
                    glyph.bb:getWidth(), glyph.bb:getHeight(),
                    color)
                pen_x = pen_x + xglyph.x_advance
            end
            return
        end
    end
    return TextWidget.paintTo(self, bb, x, y)
end

return ColorTextWidget
