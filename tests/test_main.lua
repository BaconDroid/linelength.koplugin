-- Wiring test for main.lua with KOReader stubbed out. It models source, not hardware.
package.path = "./?.lua;" .. package.path

-- ---- stubs --------------------------------------------------------------------------------
local shown, ticks, dirty, warns = {}, {}, {}, {}
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
package.preload["ui/uimanager"] = function()
    return {
        show = function(_self, w) shown[#shown + 1] = w end,
        nextTick = function(_self, fn) ticks[#ticks + 1] = fn end,
        setDirty = function(_self, widget, mode, dimen) dirty[#dirty + 1] = { widget, mode, dimen } end,
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
    return { dbg = function() end, warn = function(...) warns[#warns + 1] = { ... } end }
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

-- 1. both buttons are registered in a book
local hl = newHighlight()
makePlugin({ document = {}, ui = { highlight = hl } })
expect("count slot registered", type(hl._highlight_buttons["13_word_count"]), "function")
expect("rating slot registered", type(hl._highlight_buttons["14_line_length"]), "function")

-- 2. nothing without a document, no crash without the highlight module
local hl2 = newHighlight()
makePlugin({ document = nil, ui = { highlight = hl2 } })
expect("no document: nothing registered", next(hl2._highlight_buttons), nil)
expect("no highlight module: init does not crash", (pcall(makePlugin, { document = {}, ui = {} })), true)

local count_fn = hl._highlight_buttons["13_word_count"]
local rating_fn = hl._highlight_buttons["14_line_length"]

-- 3. count button (unchanged behaviour): cleaned like Copy
local sample = { selected_text = { text = "  Hello   world,\n\n again  " } }
local btn = count_fn(sample)
expect("count label", btn.text, "Words: 3 · Chars: 18")
expect("count button has no colour hook", btn.id, nil)
local LEGEND = "Characters per line (select one line):\n45–54  Excellent\n55–64  Comfortable\n65–74  Still readable\n75+  Too long"
btn.callback()
expect("count tap shows one popup", #shown, 1)
expect("count popup text", shown[1].text,
    "Words: 3\nCharacters, with spaces: 18\nCharacters, without spaces: 16\n\n" .. LEGEND)
expect("count label follows the selection", count_fn({ selected_text = { text = "one" } }).text, "Words: 1 · Chars: 3")
expect("nil selected_text", count_fn({}).text, "Words: 0 · Chars: 0")
expect("nil highlight", count_fn(nil).text, "Words: 0 · Chars: 0")

-- helper: press the rating button for a selection of n characters, then let the dialog "exist"
-- and run the scheduled ticks, like KOReader does right after onShowHighlightMenu returns
local function press(n, opts)
    opts = opts or {}
    ticks, dirty, warns = {}, {}, {}
    color_state.on = opts.color == nil and true or opts.color
    local label = { fgcolor = BLACK }
    if opts.textbox then
        label.updated = 0
        label.update = function(self) self.updated = self.updated + 1 end
    end
    local button = { label_widget = label, dimen = opts.dimen }
    local this = { selected_text = { text = string.rep("a", n) } }
    local b = rating_fn(this)
    if opts.dialog == "broken" then
        this.highlight_dialog = { buttontable = { button_by_id = setmetatable({}, { __index = function() error("boom") end }) } }
    elseif opts.dialog ~= "none" then
        this.highlight_dialog = { buttontable = { button_by_id = { [b.id] = button } } }
    end
    for _i, t in ipairs(ticks) do t() end
    return b, label, button
end

-- 4. every band: text and colour, at both edges (spec: #0072B2 #009E73 #E69F00 #D55E00)
local bands = {
    { 45, "Excellent", 0, 114, 178 }, { 54, "Excellent", 0, 114, 178 },
    { 55, "Comfortable", 0, 158, 115 }, { 64, "Comfortable", 0, 158, 115 },
    { 65, "Still readable", 230, 159, 0 }, { 74, "Still readable", 230, 159, 0 },
    { 75, "Too long", 213, 94, 0 }, { 200, "Too long", 213, 94, 0 },
}
for _i, c in ipairs(bands) do
    local b, label = press(c[1])
    expect("text at " .. c[1], b.text, c[2])
    expect("button id at " .. c[1], b.id, "wordcount_rating")
    expectColor("colour at " .. c[1], label.fgcolor, c[3], c[4], c[5])
end

-- 5. below 45 the text stays in the standard colour, and nothing is scheduled
for _i, n in ipairs({ 0, 1, 44 }) do
    local b, label = press(n)
    expect("short text at " .. n, b.text, "Short")
    expect("short keeps standard colour at " .. n, label.fgcolor, BLACK)
    expect("short schedules nothing at " .. n, #ticks, 0)
end

-- 6. no colour output: standard colour, text still shown, nothing scheduled
local b6, label6 = press(60, { color = false })
expect("colour off: text still shown", b6.text, "Comfortable")
expect("colour off: standard colour", label6.fgcolor, BLACK)
expect("colour off: nothing scheduled", #ticks, 0)

-- 7. isColorEnabled raising is treated as "no colour"
local b7, label7 = press(60, { color = "error" })
expect("colour check error: text still shown", b7.text, "Comfortable")
expect("colour check error: standard colour", label7.fgcolor, BLACK)

-- 8. the dialog or button is not where expected: standard colour, no crash, no warning spam
local _b8, label8 = press(60, { dialog = "none" })
expect("no dialog: standard colour", label8.fgcolor, BLACK)
expect("no dialog: no warnings", #warns, 0)

-- 9. an exception while colouring is caught and logged once
local _b9, label9 = press(60, { dialog = "broken" })
expect("broken dialog: standard colour", label9.fgcolor, BLACK)
expect("broken dialog: one warning", #warns, 1)

-- 10. redraw only when the button has been painted (has a position), TextBoxWidget gets update()
local _b10a = press(60, { dimen = { x = 10, y = 20, w = 100, h = 40 } })
expect("painted button is redrawn", #dirty, 1)
expect("redraw region", dirty[1][3].x, 10)
local _b10b = press(60)
expect("unpainted button: no extra redraw", #dirty, 0)
local _b10c, _l10c = press(60, { textbox = true })
expect("TextBoxWidget label updated once", _l10c.updated, 1)

-- 11. the rating button's tap shows the same breakdown plus the legend
local b11 = press(60)
shown = {}
b11.callback()
expect("rating tap shows one popup", #shown, 1)
expect("rating popup text", shown[1].text,
    "Words: 1\nCharacters, with spaces: 60\nCharacters, without spaces: 60\n\n" .. LEGEND)

-- 12. position: keys sort as strings; both must come after every built-in one, in this order
local builtin = { "01_select", "02_highlight", "03_copy", "04_add_note", "05_wikipedia",
    "06_dictionary", "07_translate", "08_share_text", "09_view_html", "10_user_dict",
    "11_follow_link", "12_generate_qr_code", "12_search" }
for _i, key in ipairs(builtin) do
    expect("count sorts after " .. key, "13_word_count" > key, true)
    expect("rating sorts after " .. key, "14_line_length" > key, true)
end
expect("count before rating", "13_word_count" < "14_line_length", true)

-- 13. layout: the same assembly ReaderHighlight:onShowHighlightMenu does (2 columns, sorted keys)
local function layout(keys)
    table.sort(keys)
    local rows = { {} }
    for _i, k in ipairs(keys) do
        if #rows[#rows] >= 2 then rows[#rows + 1] = {} end
        table.insert(rows[#rows], k)
    end
    return rows
end
-- the ten buttons on a Libra Colour in a normal book
local keys = { "01_select", "02_highlight", "03_copy", "04_add_note", "05_wikipedia",
    "06_dictionary", "07_translate", "09_view_html", "12_generate_qr_code", "12_search",
    "13_word_count", "14_line_length" }
local rows = layout(keys)
expect("rows", #rows, 6)
expect("count and rating share the last row", #rows[#rows], 2)
expect("count first", rows[#rows][1], "13_word_count")
expect("rating second", rows[#rows][2], "14_line_length")
expect("Search stays where it was", rows[5][2], "12_search")

if failures > 0 then
    error(failures .. " main test(s) failed")
end
print("main: all tests passed")
