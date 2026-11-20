-- Wiring test for main.lua with KOReader stubbed out. It models source, not hardware.
package.path = "./?.lua;" .. package.path

-- ---- stubs --------------------------------------------------------------------------------
local shown, warns = {}, {}
local color_state = { on = true } -- true, false, or "error" (isColorEnabled raises)
local details_opts = {}           -- what the card was asked to show

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
    function I:new(o) o.is_infomessage = true; return o end
    return I
end
-- Only show(): the button no longer schedules or refreshes anything. Any leftover use of
-- tickAfterNext/nextTick/setDirty in main.lua would raise here.
package.preload["ui/uimanager"] = function()
    return { show = function(_self, w) shown[#shown + 1] = w end }
end
-- No ffi/blitbuffer stub on purpose: main.lua must not need it any more.
package.preload["device"] = function()
    return { screen = { isColorEnabled = function()
        if color_state.on == "error" then error("no screen") end
        return color_state.on == true
    end } }
end
package.preload["logger"] = function()
    return {
        dbg = function() end,
        info = function() end,
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
-- the card is stubbed here (it is checked by rendering it in KOReader, see tests/render)
local DetailsStub = {}
function DetailsStub:new(o)
    details_opts[#details_opts + 1] = o
    return { is_details = true, opts = o }
end
package.preload["wcount/details"] = function() return DetailsStub end

local failures = 0
local function expect(name, got, want)
    if got ~= want then
        failures = failures + 1
        print(string.format("FAIL %s: got %q, want %q", name, tostring(got), tostring(want)))
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

-- 3. the button is as plain as the others: just a label and a tap handler, no colour hooks
local sample = { selected_text = { text = "  Hello   world,\n\n again  " } } -- cleaned: 18 characters
local btn = button_fn(sample)
expect("label", btn.text, "Line: 18 chars · Short")
local keys = {}
for k in pairs(btn) do keys[#keys + 1] = k end
table.sort(keys)
expect("button has only text and callback", table.concat(keys, ","), "callback,text")
expect("label follows the selection", button_fn({ selected_text = { text = "one" } }).text, "Line: 3 chars · Short")
expect("nil selected_text", button_fn({}).text, "Line: 0 chars · Short")
expect("nil text", button_fn({ selected_text = {} }).text, "Line: 0 chars · Short")
expect("nil highlight", button_fn(nil).text, "Line: 0 chars · Short")
expect("the card is not loaded until needed", package.loaded["wcount/details"], nil)

-- 4. the label at every band edge
local bands = {
    { 44, "Short" }, { 45, "Comfortable" }, { 49, "Comfortable" }, { 50, "Excellent" },
    { 66, "Excellent" }, { 67, "Comfortable" }, { 75, "Comfortable" }, { 76, "Still readable" },
    { 80, "Still readable" }, { 81, "Too long" }, { 200, "Too long" },
}
for _i, c in ipairs(bands) do
    local b = button_fn({ selected_text = { text = string.rep("a", c[1]) } })
    expect("label at " .. c[1], b.text, "Line: " .. c[1] .. " chars · " .. c[2])
end

-- 5. tapping shows the card with the report for that selection
local function tap(text, color)
    shown, warns, details_opts = {}, {}, {}
    color_state.on = color == nil and true or color
    button_fn({ selected_text = { text = text } }).callback()
end

tap(sample.selected_text.text)
expect("tap shows one widget", #shown, 1)
expect("it is the card", shown[1].is_details, true)
local report = shown[1].opts.report
expect("report chars", report.chars, 18)
expect("report chars without spaces", report.chars_no_spaces, 16)
expect("report words", report.words, 3)
expect("report verdict", report.tier.id, "short")
expect("report verdict label", report.tier.label, "Short")
expect("short has no colour", report.tier.color, nil)
expect("four ranges", #report.bands, 4)
expect("range label is translated text", report.bands[1].label, "Excellent")
expect("range 1", report.bands[1].range, "50–66")
expect("range 2 (two parts)", report.bands[2].range, "45–49, 67–75")
expect("range 4", report.bands[4].range, "81+")

tap(string.rep("a", 60))
local r60 = shown[1].opts.report
expect("60: verdict", r60.tier.id, "excellent")
expect("60: colour from the spec", r60.tier.color, "#0072B2")
expect("60: Excellent is the current range", r60.bands[1].current, true)
expect("60: Comfortable is not", r60.bands[2].current, false)

-- 6. colour is requested only when KOReader is drawing in colour
tap(string.rep("a", 60), true)
expect("colour screen: use_color", shown[1].opts.use_color, true)
tap(string.rep("a", 60), false)
expect("no colour: use_color false", shown[1].opts.use_color, false)
tap(string.rep("a", 60), "error")
expect("colour check raised: use_color false", shown[1].opts.use_color, false)

-- 7. if the card cannot be shown, the same information appears as plain text
local PLAIN = "Characters, with spaces: 18\nCharacters, without spaces: 16\nWords: 3\n\n"
    .. "Characters per line (select one line):\n50–66  Excellent\n45–49, 67–75  Comfortable\n76–80  Still readable\n81+  Too long"

-- 7a. the card module fails to load
package.loaded["wcount/details"] = nil
package.preload["wcount/details"] = function() error("boom") end
tap(sample.selected_text.text)
expect("load failure: one widget", #shown, 1)
expect("load failure: plain text popup", shown[1].is_infomessage, true)
expect("load failure: same information", shown[1].text, PLAIN)
expect("load failure: one warning", #warns, 1)

-- 7b. the card raises while it is being built
package.loaded["wcount/details"] = nil
package.preload["wcount/details"] = function()
    return { new = function() error("kaboom") end }
end
tap(sample.selected_text.text)
expect("build failure: plain text popup", shown[1] and shown[1].is_infomessage, true)
expect("build failure: same information", shown[1] and shown[1].text, PLAIN)
expect("build failure: one warning", #warns, 1)

-- back to the normal stub: the card works again afterwards
package.loaded["wcount/details"] = nil
package.preload["wcount/details"] = function() return DetailsStub end
tap(sample.selected_text.text)
expect("recovers after a failure", shown[1] and shown[1].is_details, true)

-- 8. position: keys sort as strings; ours must come after every built-in one
local builtin = { "01_select", "02_highlight", "03_copy", "04_add_note", "05_wikipedia",
    "06_dictionary", "07_translate", "08_share_text", "09_view_html", "10_user_dict",
    "11_follow_link", "12_generate_qr_code", "12_search" }
for _i, key in ipairs(builtin) do
    expect("sorts after " .. key, "13_line_length" > key, true)
end

-- 9. layout: the same assembly ReaderHighlight:onShowHighlightMenu does (2 columns, sorted keys)
local function layout(ks)
    table.sort(ks)
    local rows = { {} }
    for _i, k in ipairs(ks) do
        if #rows[#rows] >= 2 then rows[#rows + 1] = {} end
        table.insert(rows[#rows], k)
    end
    return rows
end
local ks = { "01_select", "02_highlight", "03_copy", "04_add_note", "05_wikipedia",
    "06_dictionary", "07_translate", "09_view_html", "12_generate_qr_code", "12_search",
    "13_line_length" }
local rows = layout(ks)
expect("rows", #rows, 6)
expect("ours is alone on a full-width last row", #rows[#rows], 1)
expect("and it is ours", rows[#rows][1], "13_line_length")
expect("Search stays where it was", rows[5][2], "12_search")

if failures > 0 then
    error(failures .. " main test(s) failed")
end
print("main: all tests passed")
