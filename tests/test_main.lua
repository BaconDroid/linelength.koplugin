-- Wiring test for main.lua with KOReader stubbed out. It models source, not hardware.
package.path = "./?.lua;" .. package.path

-- ---- stubs --------------------------------------------------------------------------------
local shown, warns = {}, {}
local color_state = { on = true } -- true, false, or "error" (isColorEnabled raises)
local screen_state = { raises = false } -- true: asking for the screen size raises
local details_opts = {}           -- what the card was asked to show
local actions = {}                -- Dispatcher actions registered

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
    return { screen = {
        isColorEnabled = function()
            if color_state.on == "error" then error("no screen") end
            return color_state.on == true
        end,
        getWidth = function()
            if screen_state.raises then error("no screen size") end
            return 1264
        end,
        getHeight = function() return 1680 end,
    } }
end
package.preload["dispatcher"] = function()
    return { registerAction = function(_self, name, def) actions[name] = def end }
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
package.preload["linelength/details"] = function() return DetailsStub end

local failures = 0
local function expect(name, got, want)
    if got ~= want then
        failures = failures + 1
        print(string.format("FAIL %s: got %q, want %q", name, tostring(got), tostring(want)))
    end
end

local LineLength = require("main")
expect("plugin name", LineLength.name, "linelength")
expect("only loads inside a book", LineLength.is_doc_only, true)

local function newHighlight()
    local h = { _highlight_buttons = {} }
    function h:addToHighlightDialog(idx, fn) self._highlight_buttons[idx] = fn end
    return h
end

local function makePlugin(opts)
    local p = LineLength:new({ document = opts.document, ui = opts.ui })
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
expect("the card is not loaded until needed", package.loaded["linelength/details"], nil)

-- 4. the label at every band edge
local bands = {
    { 44, "Short" }, { 45, "Short" }, { 49, "Short" }, { 50, "Excellent" },
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
expect("range 2", report.bands[2].range, "67–75")
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
    .. "Characters per line (select one line):\n50–66  Excellent\n67–75  Comfortable\n76–80  Still readable\n81+  Too long"

-- 7a. the card module fails to load
package.loaded["linelength/details"] = nil
package.preload["linelength/details"] = function() error("boom") end
tap(sample.selected_text.text)
expect("load failure: one widget", #shown, 1)
expect("load failure: plain text popup", shown[1].is_infomessage, true)
expect("load failure: same information", shown[1].text, PLAIN)
expect("load failure: one warning", #warns, 1)

-- 7b. the card raises while it is being built
package.loaded["linelength/details"] = nil
package.preload["linelength/details"] = function()
    return { new = function() error("kaboom") end }
end
tap(sample.selected_text.text)
expect("build failure: plain text popup", shown[1] and shown[1].is_infomessage, true)
expect("build failure: same information", shown[1] and shown[1].text, PLAIN)
expect("build failure: one warning", #warns, 1)

-- back to the normal stub: the card works again afterwards
package.loaded["linelength/details"] = nil
package.preload["linelength/details"] = function() return DetailsStub end
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

-- ---------------------------------------------------------------------------------------------
-- 10. the whole-page measurement
local function fakeDoc(line_texts, opts)
    opts = opts or {}
    local NODE = "/b/p[1]/text()[1]"
    local lines, offset = {}, 0
    for i, s in ipairs(line_texts) do
        lines[i] = { s = s, from = offset, to = offset + #s, y = 71 + (i - 1) * 64 }
        offset = offset + #s + 1
    end
    local d = {}
    function d:getTextFromPositions(p0, _p1)
        if opts.raises then error("engine boom") end
        if p0.y == 0 then
            local boxes = {}
            for _i, l in ipairs(lines) do boxes[#boxes + 1] = { x = 43, y = l.y, w = 1180, h = 64 } end
            return { text = "page", pos0 = NODE .. ".0", pos1 = NODE .. "." .. offset, sboxes = boxes }
        end
        for _i, l in ipairs(lines) do
            if p0.y >= l.y and p0.y < l.y + 64 then
                return { text = l.s, pos0 = NODE .. "." .. l.from, pos1 = NODE .. "." .. l.to }
            end
        end
    end
    function d:getScreenPositionFromXPointer(xp)
        local off = tonumber(xp:match("%.(%d+)$"))
        for _i, l in ipairs(lines) do
            if off >= l.from and off <= l.to then return l.y, 43 end
        end
        return 0, 0
    end
    function d:getTextFromXPointers() return "" end
    return d
end

-- three lines: 59 characters ("word " x12 without the last space), 70, and 45
local L1 = ("word "):rep(12):sub(1, -2)
local L2 = ("b"):rep(70)
local L3 = ("c"):rep(45)
expect("test line 1 is 59 characters", #L1, 59)

local function newMenu()
    return { registered = {}, registerToMainMenu = function(self, p) self.registered[#self.registered + 1] = p end }
end
local function pagePlugin(doc, opts)
    opts = opts or {}
    actions = {}
    local menu = newMenu()
    local p = makePlugin({ document = {}, ui = { menu = menu, highlight = newHighlight(), document = doc, rolling = opts.rolling == nil and {} or opts.rolling } })
    return p, menu
end
local function reset() shown, warns, details_opts, screen_state.raises, color_state.on = {}, {}, {}, false, true end

-- 10a. registration: the action, the menu, and the selection button together
local plugin, menu = pagePlugin(fakeDoc({ L1, L2, L3 }))
-- the action id is still "wordcount_page", the plugin's old name, on purpose: gestures and profiles store it
local action = actions["wordcount_page"]
expect("action registered", type(action), "table")
expect("action event", action and action.event, "LinelengthPage")
expect("action title", action and action.title, "Line length: this page")
expect("action is only for books that reflow", action and action.rolling, true)
expect("and is not marked for every book type", action and action.reader, nil)
expect("action has no category", action and action.category, "none")
expect("registered with the menu once", #menu.registered, 1)
expect("registered as this plugin", menu.registered[1], plugin)
local items = {}
plugin:addToMainMenu(items)
expect("menu item text", items.linelength_page and items.linelength_page.text, "Line length: this page")
expect("menu item goes in the Typeset menu", items.linelength_page and items.linelength_page.sorting_hint, "typeset")
local item_count = 0
for _k in pairs(items) do item_count = item_count + 1 end
expect("one menu item", item_count, 1)

-- 10b. nothing in the file manager (no document); a bare ui does not crash and still offers the action
actions = {}
local bare_menu = newMenu()
makePlugin({ document = nil, ui = { menu = bare_menu } })
expect("no document: no action", next(actions), nil)
expect("no document: no menu", #bare_menu.registered, 0)
actions = {}
expect("no menu and no highlight: init does not crash", (pcall(makePlugin, { document = {}, ui = {} })), true)
expect("no menu and no highlight: the action is still registered", type(actions["wordcount_page"]), "table")
actions = {}
local only_menu = newMenu()
makePlugin({ document = {}, ui = { menu = only_menu } })
expect("a menu without the highlight module", #only_menu.registered, 1)

-- 10c. the menu item shows the card: the longest line sets the rating, three lines are listed
reset()
items = {}
plugin:addToMainMenu(items)
items.linelength_page.callback()
expect("menu item shows one widget", #shown, 1)
expect("it is the card", shown[1] and shown[1].is_details, true)
local pr = shown[1] and shown[1].opts.report
expect("page report: the longest line (70)", pr and pr.chars, 70)
expect("page report: verdict follows the longest line", pr and pr.tier.id, "comfortable")
expect("page report: colour of that band", pr and pr.tier.color, "#009E73")
expect("page report: Comfortable is the current range", pr and pr.bands[2].current, true)
expect("page report: Excellent is not", pr and pr.bands[1].current, false)
expect("page report: three lines listed", pr and #pr.lines, 3)
expect("page report: longest first (70)", pr and pr.lines[1].chars, 70)
expect("page report: then 59", pr and pr.lines[2].chars, 59)
expect("page report: then 45", pr and pr.lines[3].chars, 45)
expect("page report: long line cut to 32 characters and an ellipsis", pr and pr.lines[1].snippet, ("b"):rep(32) .. "…")
expect("page report: snippet shows the start of the text", pr and pr.lines[2].snippet, "word word word word word word wo…")
-- the page order is 59, 70, 45 (top to bottom), so by length the lines are the 2nd, the 1st and the 3rd
expect("page report: the longest is line 2 of the page", pr and pr.lines[1].number, 2)
expect("page report: the second longest is line 1 of the page", pr and pr.lines[2].number, 1)
expect("page report: the third is line 3 of the page", pr and pr.lines[3].number, 3)
expect("card asked for colour on a colour screen", shown[1].opts.use_color, true)

-- 10d. the gesture action does the same, and says it handled the event
reset()
expect("the action handler reports it handled the event", plugin:onLinelengthPage(), true)
expect("the action shows the card too", shown[1] and shown[1].is_details, true)

-- 10e. fewer than three lines: only those are listed
reset()
local small = pagePlugin(fakeDoc({ L2, L3 }))
small:onLinelengthPage()
expect("two lines on the page: two listed", shown[1] and #shown[1].opts.report.lines, 2)
reset()
local single = pagePlugin(fakeDoc({ L3 }))
single:onLinelengthPage()
expect("one line: 45 is Short, no colour", shown[1] and shown[1].opts.report.tier.id, "short")

-- 10f. nothing to measure
reset()
local unsupported = pagePlugin(fakeDoc({ L1 }), { rolling = false })
unsupported.ui.rolling = nil
unsupported:onLinelengthPage()
expect("a book that does not reflow: a message", shown[1] and shown[1].is_infomessage, true)
expect("and it says why", shown[1] and shown[1].text, "This only works in books that reflow, like EPUB.")
reset()
local no_methods = pagePlugin({})
no_methods:onLinelengthPage()
expect("an engine without the line functions: same message", shown[1] and shown[1].text, "This only works in books that reflow, like EPUB.")
reset()
local blank = pagePlugin(fakeDoc({}))
blank:onLinelengthPage()
expect("a page without text: a message", shown[1] and shown[1].is_infomessage, true)
expect("and it says so", shown[1] and shown[1].text, "There is no text on this page.")
reset()
local broken_engine = pagePlugin(fakeDoc({ L1 }, { raises = true }))
broken_engine:onLinelengthPage()
expect("an engine that raises reads as an empty page", shown[1] and shown[1].text, "There is no text on this page.")
expect("without a crash or a warning", #warns, 0)

-- an engine that has two of the three line functions is still not enough
for _i, missing in ipairs({ "getTextFromXPointers", "getScreenPositionFromXPointer", "getTextFromPositions" }) do
    reset()
    local doc = fakeDoc({ L1 })
    doc[missing] = nil
    pagePlugin(doc):onLinelengthPage()
    expect("an engine without " .. missing .. ": not supported", shown[1] and shown[1].text, "This only works in books that reflow, like EPUB.")
end

-- the page is read the way the highlight button reads a selection: spaces collapsed first
reset()
pagePlugin(fakeDoc({ ("x"):rep(10) .. "   " .. ("y"):rep(10) })):onLinelengthPage()
expect("three spaces count as one (10 + 1 + 10)", shown[1] and shown[1].opts.report.chars, 21)

-- 10g. anything unexpected is caught and reported, never raised into KOReader
reset()
screen_state.raises = true
plugin:onLinelengthPage()
expect("unexpected error: a message is shown", shown[1] and shown[1].is_infomessage, true)
expect("unexpected error: it says what failed", shown[1] and shown[1].text, "Could not read the lines of this page.")
expect("unexpected error: one warning", #warns, 1)
screen_state.raises = false

-- 10h. the card fails: the same information as plain text
local PLAIN_PAGE = "Longest lines on this page (characters):\n"
    .. "L2: " .. ("b"):rep(32) .. "…  70\n"
    .. "L1: word word word word word word wo…  59\n"
    .. "L3: " .. ("c"):rep(32) .. "…  45\n\n"
    .. "50–66  Excellent\n67–75  Comfortable\n76–80  Still readable\n81+  Too long"
reset()
package.loaded["linelength/details"] = nil
package.preload["linelength/details"] = function() error("boom") end
plugin:onLinelengthPage()
expect("card load failure: plain text popup", shown[1] and shown[1].is_infomessage, true)
expect("card load failure: the lines and the ranges", shown[1] and shown[1].text, PLAIN_PAGE)
expect("card load failure: one warning", #warns, 1)
package.loaded["linelength/details"] = nil
package.preload["linelength/details"] = function() return DetailsStub end

-- 10i. the selection button is unaffected by all this
reset()
tap(sample.selected_text.text)
expect("selection button still shows the selection report", shown[1] and shown[1].opts.report.lines, nil)
expect("selection report keeps its counts", shown[1] and shown[1].opts.report.chars, 18)

if failures > 0 then
    error(failures .. " main test(s) failed")
end
print("main: all tests passed")
