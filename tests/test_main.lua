-- Wiring test for main.lua with KOReader stubbed out. It models source, not hardware.
package.path = "./?.lua;" .. package.path

-- ---- stubs --------------------------------------------------------------------------------
local shown, ticks, dirty, warns, infos = {}, {}, {}, {}, {}
local color_state = { on = true } -- true, false, or "error" (isColorEnabled raises)
local BLACK = { black = true }

local function extend(base, t)
    t = t or {}
    t.__index = t
    setmetatable(t, { __index = base })
    t.extend = function(self, tt) return extend(self, tt) end
    t.new = function(self, o) o = o or {}; setmetatable(o, self); return o end
    return t
end

package.preload["ui/widget/container/widgetcontainer"] = function()
    local W = { extend = function(self, t) return extend(self, t) end }
    W.__index = W
    return W
end
package.preload["ui/widget/infomessage"] = function()
    local I = {}
    function I:new(o) return o end
    return I
end
-- Deliberately no nextTick: the plugin must wait for the dialog's first paint (tickAfterNext).
package.preload["ui/uimanager"] = function()
    return {
        show = function(_self, w) shown[#shown + 1] = w end,
        tickAfterNext = function(_self, fn) ticks[#ticks + 1] = fn end,
        setDirty = function(_self, widget, mode, dimen, dither)
            dirty[#dirty + 1] = { widget = widget, mode = mode, dimen = dimen, dither = dither }
        end,
    }
end
package.preload["ffi/blitbuffer"] = function()
    return {
        COLOR_BLACK = BLACK,
        ColorRGB32 = function(r, g, b, a) return { r = r, g = g, b = b, a = a } end,
    }
end
package.preload["device"] = function()
    return { screen = { isColorEnabled = function()
        if color_state.on == "error" then error("no screen") end
        return color_state.on == true
    end } }
end
package.preload["logger"] = function()
    return {
        dbg = function() end,
        info = function(...) infos[#infos + 1] = { ... } end,
        warn = function(...) warns[#warns + 1] = { ... } end,
    }
end
package.preload["gettext"] = function() return function(s) return s end end
package.preload["ffi/util"] = function()
    return { template = function(str, ...)
        local args = { ... }
        return (str:gsub("%%([0-9]+)", function(i) return tostring(args[tonumber(i)]) end))
    end }
end
-- the real KOReader implementation (frontend/util.lua, v2026.07.1), copied verbatim
package.preload["util"] = function()
    local util = {}
    function util.cleanupSelectedText(text)
        text = text:gsub("^[\n%s]*", "")
        text = text:gsub("[\n%s]*$", "")
        text = text:gsub("%s*\n%s*", "\n")
        text = text:gsub("%s%s+", " ")
        return text
    end
    return util
end

local failures = 0
local function expect(name, got, want)
    if got ~= want then
        failures = failures + 1
        print(string.format("FAIL %s: got %q, want %q", name, tostring(got), tostring(want)))
    end
end
local function expectColor(name, c, r, g, b)
    if type(c) ~= "table" or c.r ~= r or c.g ~= g or c.b ~= b or c.a ~= 255 then
        failures = failures + 1
        local got = type(c) == "table" and (c.black and "BLACK" or (tostring(c.r) .. "," .. tostring(c.g) .. "," .. tostring(c.b))) or tostring(c)
        print(string.format("FAIL %s: got %s, want %d,%d,%d", name, got, r, g, b))
    end
end

local WordCount = require("main")
expect("plugin name", WordCount.name, "wordcount")
expect("only loads inside a book", WordCount.is_doc_only, true)

local function newHighlight()
    local h = { _highlight_buttons = {} }
    function h:addToHighlightDialog(idx, fn) self._highlight_buttons[idx] = fn end
    return h
end

local function makePlugin(opts)
    local p = WordCount:new({ document = opts.document, ui = opts.ui })
    p:init()
    return p
end

-- 1. exactly one button is registered in a book, in the last slot
local hl = newHighlight()
makePlugin({ document = {}, ui = { highlight = hl } })
expect("slot registered", type(hl._highlight_buttons["13_line_length"]), "function")
local registered = 0
for _k in pairs(hl._highlight_buttons) do registered = registered + 1 end
expect("only one button", registered, 1)

-- 2. nothing without a document, no crash without the highlight module
local hl2 = newHighlight()
makePlugin({ document = nil, ui = { highlight = hl2 } })
expect("no document: nothing registered", next(hl2._highlight_buttons), nil)
expect("no highlight module: init does not crash", (pcall(makePlugin, { document = {}, ui = {} })), true)

local button_fn = hl._highlight_buttons["13_line_length"]

-- 3. label for a selection (cleaned like Copy: ends trimmed, spaces collapsed): 18 characters
local sample = { selected_text = { text = "  Hello   world,\n\n again  " } }
local btn = button_fn(sample)
expect("label", btn.text, "Line: 18 chars · Short")
expect("button id", btn.id, "wordcount_line_length")
local LEGEND = "Characters per line (select one line):\n45–54  Excellent\n55–64  Comfortable\n65–74  Still readable\n75+  Too long"
btn.callback()
expect("tap shows one popup", #shown, 1)
expect("popup text", shown[1].text,
    "Characters, with spaces: 18\nCharacters, without spaces: 16\nWords: 3\n\n" .. LEGEND)
expect("label follows the selection", button_fn({ selected_text = { text = "one" } }).text, "Line: 3 chars · Short")
expect("nil selected_text", button_fn({}).text, "Line: 0 chars · Short")
expect("nil text", button_fn({ selected_text = {} }).text, "Line: 0 chars · Short")
expect("nil highlight", button_fn(nil).text, "Line: 0 chars · Short")

-- helper: press the button for a selection of n characters, then let the dialog "exist" and run
-- the scheduled ticks, like KOReader does two UI ticks after onShowHighlightMenu returns
local function press(n, opts)
    opts = opts or {}
    ticks, dirty, warns, infos = {}, {}, {}, {}
    color_state.on = opts.color == nil and true or opts.color
    local label = { fgcolor = BLACK }
    if opts.textbox then
        label.updated = 0
        label.update = function(self) self.updated = self.updated + 1 end
    end
    local button = { label_widget = label, dimen = opts.dimen }
    local this = { selected_text = { text = string.rep("a", n) } }
    local b = button_fn(this)
    local dialog = { dimen = opts.dialog_dimen }
    if opts.dialog == "broken" then
        dialog.buttontable = { button_by_id = setmetatable({}, { __index = function() error("boom") end }) }
        this.highlight_dialog = dialog
    elseif opts.dialog ~= "none" then
        dialog.buttontable = { button_by_id = { [b.id] = button } }
        this.highlight_dialog = dialog
    end
    for _i, t in ipairs(ticks) do t() end
    return b, label, button, dialog
end

-- 4. every band: text and colour, at both edges (spec: #0072B2 #009E73 #E69F00 #D55E00)
local bands = {
    { 45, "Line: 45 chars · Excellent", 0, 114, 178 },
    { 54, "Line: 54 chars · Excellent", 0, 114, 178 },
    { 55, "Line: 55 chars · Comfortable", 0, 158, 115 },
    { 64, "Line: 64 chars · Comfortable", 0, 158, 115 },
    { 65, "Line: 65 chars · Still readable", 230, 159, 0 },
    { 74, "Line: 74 chars · Still readable", 230, 159, 0 },
    { 75, "Line: 75 chars · Too long", 213, 94, 0 },
    { 200, "Line: 200 chars · Too long", 213, 94, 0 },
}
for _i, c in ipairs(bands) do
    local b, label = press(c[1])
    expect("text at " .. c[1], b.text, c[2])
    expectColor("colour at " .. c[1], label.fgcolor, c[3], c[4], c[5])
    expect("one tick scheduled at " .. c[1], #ticks, 1)
end

-- 5. below 45 the text stays in the standard colour, and nothing is scheduled
for _i, n in ipairs({ 0, 1, 44 }) do
    local b, label = press(n)
    expect("short text at " .. n, b.text, "Line: " .. n .. " chars · Short")
    expect("short keeps standard colour at " .. n, label.fgcolor, BLACK)
    expect("short schedules nothing at " .. n, #ticks, 0)
end

-- 6. no colour output: standard colour, text still shown, nothing scheduled, no refresh
local b6, label6 = press(60, { color = false, dimen = { x = 1, y = 2, w = 3, h = 4 } })
expect("colour off: text still shown", b6.text, "Line: 60 chars · Comfortable")
expect("colour off: standard colour", label6.fgcolor, BLACK)
expect("colour off: nothing scheduled", #ticks, 0)
expect("colour off: no refresh", #dirty, 0)

-- 7. isColorEnabled raising is treated as "no colour"
local b7, label7 = press(60, { color = "error" })
expect("colour check error: text still shown", b7.text, "Line: 60 chars · Comfortable")
expect("colour check error: standard colour", label7.fgcolor, BLACK)

-- 8. the dialog or button is not where expected: standard colour, no crash, one warning in the log
local _b8, label8 = press(60, { dialog = "none" })
expect("no dialog: standard colour", label8.fgcolor, BLACK)
expect("no dialog: one warning explains why", #warns, 1)

-- 9. an exception while colouring is caught and logged once
local _b9, label9 = press(60, { dialog = "broken" })
expect("broken dialog: standard colour", label9.fgcolor, BLACK)
expect("broken dialog: one warning", #warns, 1)

-- 10. the colour refresh: dithered "partial" (the only kind that reaches a colour waveform on
-- Kaleido screens; a "ui" refresh would stay greyscale), on the button's area
local dimen = { x = 10, y = 20, w = 100, h = 40 }
local _b10, _l10, _btn10, dialog10 = press(60, { dimen = dimen })
expect("one refresh requested", #dirty, 1)
expect("refresh widget is the dialog", dirty[1].widget, dialog10)
expect("refresh type is partial", dirty[1].mode, "partial")
expect("refresh region is the button", dirty[1].dimen, dimen)
expect("refresh is dithered", dirty[1].dither, true)
expect("success is logged once", #infos, 1)

-- button not laid out yet: fall back to the dialog's area
local dialog_dimen = { x = 0, y = 100, w = 900, h = 600 }
local _b10b, _l10b, _btn10b, dialog10b = press(60, { dialog_dimen = dialog_dimen })
expect("fallback refresh requested", #dirty, 1)
expect("fallback region is the dialog", dirty[1].dimen, dialog_dimen)
expect("fallback is dithered partial", dirty[1].mode .. tostring(dirty[1].dither), "partialtrue")

-- no region at all: colour is still set, no refresh is requested, and the log says so
local _b10c, l10c = press(60)
expectColor("no region: colour still set", l10c.fgcolor, 0, 158, 115)
expect("no region: no refresh", #dirty, 0)
expect("no region: logged", infos[1][4], "no region to refresh")

-- a TextBoxWidget label needs update() to take the colour
local _b10d, l10d = press(60, { textbox = true })
expect("TextBoxWidget label updated once", l10d.updated, 1)

-- 11. position: keys sort as strings; ours must come after every built-in one
local builtin = { "01_select", "02_highlight", "03_copy", "04_add_note", "05_wikipedia",
    "06_dictionary", "07_translate", "08_share_text", "09_view_html", "10_user_dict",
    "11_follow_link", "12_generate_qr_code", "12_search" }
for _i, key in ipairs(builtin) do
    expect("sorts after " .. key, "13_line_length" > key, true)
end

-- 12. layout: the same assembly ReaderHighlight:onShowHighlightMenu does (2 columns, sorted keys)
local function layout(keys)
    table.sort(keys)
    local rows = { {} }
    for _i, k in ipairs(keys) do
        if #rows[#rows] >= 2 then rows[#rows + 1] = {} end
        table.insert(rows[#rows], k)
    end
    return rows
end
-- the ten buttons on a Libra Colour in a normal book, plus ours
local keys = { "01_select", "02_highlight", "03_copy", "04_add_note", "05_wikipedia",
    "06_dictionary", "07_translate", "09_view_html", "12_generate_qr_code", "12_search",
    "13_line_length" }
local rows = layout(keys)
expect("rows", #rows, 6)
expect("ours is alone on a full-width last row", #rows[#rows], 1)
expect("and it is ours", rows[#rows][1], "13_line_length")
expect("Search stays where it was", rows[5][2], "12_search")

if failures > 0 then
    error(failures .. " main test(s) failed")
end
print("main: all tests passed")
