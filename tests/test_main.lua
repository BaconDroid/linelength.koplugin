-- Wiring test for main.lua with KOReader stubbed out. It models source, not hardware.
package.path = "./?.lua;" .. package.path

-- ---- stubs --------------------------------------------------------------------------------
local shown = {}
local registered = {}

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
    return { show = function(_self, w) shown[#shown + 1] = w end }
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

local WordCount = require("main")
expect("plugin name", WordCount.name, "wordcount")
expect("only loads inside a book", WordCount.is_doc_only, true)

local function newHighlight()
    local h = { _highlight_buttons = {} }
    function h:addToHighlightDialog(idx, fn) self._highlight_buttons[idx] = fn end
    return h
end

local function makePlugin(opts)
    local o = { document = opts.document, ui = opts.ui }
    local p = WordCount:new(o)
    p:init()
    return p
end

-- 1. registers in a book
local hl = newHighlight()
makePlugin({ document = {}, ui = { highlight = hl } })
expect("slot registered", type(hl._highlight_buttons["13_word_count"]), "function")

-- 2. not registered without a document, and no crash without the highlight module
local hl2 = newHighlight()
makePlugin({ document = nil, ui = { highlight = hl2 } })
expect("no document: nothing registered", next(hl2._highlight_buttons), nil)
local ok = pcall(makePlugin, { document = {}, ui = {} })
expect("no highlight module: init does not crash", ok, true)

-- 3. label for a selection (cleaned like Copy: ends trimmed, spaces collapsed)
local fn = hl._highlight_buttons["13_word_count"]
local btn = fn({ selected_text = { text = "  Hello   world,\n\n again  " } })
expect("label", btn.text, "Words: 3 · Chars: 18")
btn.callback()
expect("tap shows one popup", #shown, 1)
expect("popup text", shown[1].text,
    "Words: 3\nCharacters, with spaces: 18\nCharacters, without spaces: 16")

-- 4. the label follows the selection, it is not cached
local btn2 = fn({ selected_text = { text = "one" } })
expect("second selection", btn2.text, "Words: 1 · Chars: 3")

-- 5. missing selection text must not crash
expect("nil selected_text", fn({}).text, "Words: 0 · Chars: 0")
expect("nil text", fn({ selected_text = {} }).text, "Words: 0 · Chars: 0")
expect("nil highlight", fn(nil).text, "Words: 0 · Chars: 0")

-- 6. position: KOReader sorts the keys as strings; ours must come after every built-in one
local builtin = { "01_select", "02_highlight", "03_copy", "04_add_note", "05_wikipedia",
    "06_dictionary", "07_translate", "08_share_text", "09_view_html", "10_user_dict",
    "11_follow_link", "12_generate_qr_code", "12_search" }
for _i, key in ipairs(builtin) do
    expect("sorts after " .. key, "13_word_count" > key, true)
end

-- 7. layout: the same assembly ReaderHighlight:onShowHighlightMenu does (2 columns, sorted keys)
local function layout(keys)
    table.sort(keys)
    local rows = { {} }
    for _i, k in ipairs(keys) do
        if #rows[#rows] >= 2 then rows[#rows + 1] = {} end
        table.insert(rows[#rows], k)
    end
    return rows
end
-- the ten buttons on a Libra Colour in a normal book: Select Highlight Copy Add-note Wikipedia
-- Dictionary Translate View-HTML QR Search
local ten = { "01_select", "02_highlight", "03_copy", "04_add_note", "05_wikipedia",
    "06_dictionary", "07_translate", "09_view_html", "12_generate_qr_code", "12_search" }
local keys = {}
for _i, k in ipairs(ten) do keys[#keys + 1] = k end
keys[#keys + 1] = "13_word_count"
local rows = layout(keys)
expect("rows", #rows, 6)
expect("count is alone on the last row", #rows[#rows], 1)
expect("and it is ours", rows[#rows][1], "13_word_count")
expect("Search stays where it was", rows[5][2], "12_search")

if failures > 0 then
    error(failures .. " main test(s) failed")
end
print("main: all tests passed")
