-- End-to-end check of the plugin in a desktop build of KOReader: the real main.lua, the real text engine
-- (crengine) on a real book, and the real details card, all together. It opens a book, goes to a page,
-- runs "Line length: this page" the way the menu does, and saves a screenshot of the book page with the
-- card on top. It models the code, not the Kaleido panel.
--   cd <KOReader.app>/Contents/koreader
--   HOME=<empty dir> PLUGIN_DIR=<this repo> BOOK=<an .epub> PAGE=2 SHOT_DIR=<out dir> SDL_VIDEODRIVER=dummy \
--     EMULATE_READER_W=1264 EMULATE_READER_H=1680 EMULATE_READER_DPI=300 ./luajit <this repo>/tests/plugin.lua
io.stdout:setvbuf("line")
os.setlocale("C", "numeric")
require("setupkoenv")
G_defaults = require("luadefaults"):open()
local DataStorage = require("datastorage")
G_reader_settings = require("luasettings"):open(DataStorage:getDataDir() .. "/settings.reader.lua")
local Device = require("device")
require("document/canvascontext"):init(Device)
require("ui/bidi").setup(nil)
local _bb = require("ffi/blitbuffer")
_bb:setUseCBB(true)
_bb:enableCBB(true)

local Geom = require("ui/geometry")
local UIManager = require("ui/uimanager")
local Screen = Device.screen
local util = require("util")

local PLUGIN = os.getenv("PLUGIN_DIR")
package.path = PLUGIN .. "/?.lua;" .. package.path
local PageLines = require("wcount/pagelines")

local failures = 0
local function check(name, ok, detail)
    print(string.format("%s  %s%s", ok and "PASS" or "FAIL", name, detail and ("  (" .. tostring(detail) .. ")") or ""))
    if not ok then failures = failures + 1 end
end

-- the book, laid out like a Libra Colour page
local doc = require("document/documentregistry"):openDocument(os.getenv("BOOK"))
doc:setViewDimen(Screen:getSize())
doc:setFontFace("Noto Serif")
doc:setFontSize(Screen:scaleBySize(22))
doc:setPageMargins(Screen:scaleBySize(20), Screen:scaleBySize(20), Screen:scaleBySize(20), Screen:scaleBySize(20))
doc:render()
local page = tonumber(os.getenv("PAGE") or "2")
doc:gotoPage(page)

-- a stand-in for ReaderUI: only what the plugin touches
local registered_menu, highlight_slots = {}, {}
local ui = {
    document = doc,
    rolling = {},
    menu = { registerToMainMenu = function(_self, p) registered_menu[#registered_menu + 1] = p end },
    highlight = { addToHighlightDialog = function(_self, key, fn) highlight_slots[key] = fn end },
}

-- the real plugin file. KOReader's own :new calls init(), so it is not called again here.
local WordCount = dofile(PLUGIN .. "/main.lua")
local plugin = WordCount:new{ document = doc, ui = ui }
check("the plugin registered itself with the menu", #registered_menu == 1 and registered_menu[1] == plugin)
check("the selection button is still registered", type(highlight_slots["13_line_length"]) == "function")
local Dispatcher = require("dispatcher")

-- the menu item, built the way KOReader builds it
local items = {}
plugin:addToMainMenu(items)
check("a Typeset menu item exists", items.wordcount_page and items.wordcount_page.sorting_hint == "typeset")

-- what the page really holds, worked out independently of main.lua
local lines = PageLines.collect(doc, Screen:getWidth(), Screen:getHeight(), util.cleanupSelectedText)
local expected = PageLines.longest(lines, 3)
print(string.format("page %d: %d lines; longest three: %d, %d, %d", page, #lines, expected[1].chars, expected[2].chars, expected[3].chars))

-- show the page under the card, then run the menu item
local shown
local real_show = UIManager.show
UIManager.show = function(self, widget, ...)
    if widget.report then shown = widget end
    return real_show(self, widget, ...)
end
local events_seen = {}
local page_widget = {
    dimen = Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() },
    getSize = function(self) return self.dimen end,
    paintTo = function(self, bb, x, y)
        bb:paintRect(x, y, self.dimen.w, self.dimen.h, _bb.COLOR_WHITE)
        doc:drawCurrentView(bb, x, y, self.dimen, 0)
    end,
    -- the reader window: events sent by KOReader reach the plugin the way ReaderUI forwards them
    handleEvent = function(_self, event)
        events_seen[#events_seen + 1] = event.handler
        if event.handler == "onWordcountPage" then return plugin:onWordcountPage() end
        return false
    end,
}
real_show(UIManager, page_widget)
UIManager:forceRePaint()
-- the bare page, for counting its lines by eye against the numbers on the card
Screen:shot((os.getenv("SHOT_DIR") or ".") .. "/page_only.png")
items.wordcount_page.callback()
UIManager:forceRePaint()

check("the menu item showed a card", shown ~= nil)
if shown then
    local r = shown.report
    check("the card's longest line matches the page", r.chars == expected[1].chars, r.chars .. " vs " .. expected[1].chars)
    check("three lines are listed", #r.lines == 3)
    check("they are the page's three longest",
        r.lines[1].chars == expected[1].chars and r.lines[2].chars == expected[2].chars and r.lines[3].chars == expected[3].chars)
    check("the verdict has a label", type(r.tier.label) == "string" and r.tier.label ~= "")
    print(string.format("card: %d characters, %s; lines %d, %d, %d", r.chars, r.tier.label, r.lines[1].chars, r.lines[2].chars, r.lines[3].chars))
    for i, l in ipairs(r.lines) do print(string.format("  L%-2d %3d  %s", l.number or 0, l.chars, l.snippet)) end

    -- Each listed line carries its own place on the page. Checked independently of the plugin's numbering:
    -- line N of the page (counted by this test from the list of all lines) must be the one whose text the row shows.
    local seen_numbers = {}
    for i, l in ipairs(r.lines) do
        local n = l.number
        check("listed line " .. i .. " has a whole-number place on the page", type(n) == "number" and n == math.floor(n) and n >= 1 and n <= #lines, tostring(n))
        check("listed line " .. i .. " (L" .. tostring(n) .. ") is the page's line " .. tostring(n),
            n ~= nil and lines[n] ~= nil and PageLines.snippet(lines[n].text, 32) == l.snippet, l.snippet)
        check("listed line " .. i .. " has a different number from the others", not seen_numbers[n])
        seen_numbers[n] = true
    end

    -- the text the card really draws, found in the widget tree: the bold heading and one "L<n>:" label per row
    local Font = require("ui/font")
    -- a face is bold when its font file is: Font:getFace reports the file as realname (e.g. NotoSans-Bold.ttf)
    local function isBold(face) return type(face.realname) == "string" and face.realname:find("Bold", 1, true) ~= nil end
    check("the test's own idea of a bold face: bold font is bold, the regular list font is not",
        isBold(Font:getFace("smallinfofontbold")) and not isBold(Font:getFace("xx_smallinfofont")))
    local function findText(root, text)
        local seen, found = {}, nil
        local function walk(w, depth)
            if type(w) ~= "table" or seen[w] or depth > 30 or found then return end
            seen[w] = true
            if w.text == text and w.face then found = w; return end
            for _i, child in ipairs(w) do walk(child, depth + 1) end
        end
        walk(root, 0)
        return found
    end
    local heading = findText(shown, "Longest lines on this page:")
    check("the card has the heading 'Longest lines on this page:' (with the colon)", heading ~= nil)
    check("the heading is bold", heading ~= nil and isBold(heading.face), heading and heading.face.realname)
    for i, l in ipairs(r.lines) do
        local label = findText(shown, "L" .. l.number .. ":")
        check("row " .. i .. " shows the label L" .. l.number .. ":", label ~= nil)
        check("row " .. i .. "'s label is bold", label ~= nil and isBold(label.face))
    end

    -- the card as the real widget built it: the X is in the top right corner and closes the card
    local card = shown.frame and shown.frame.dimen
    local x_button = shown.titlebar and shown.titlebar.right_button
    check("the card has a title bar with an X button", x_button ~= nil)
    if x_button and card then
        local b = x_button.dimen
        print(string.format("card at x=%d y=%d w=%d h=%d; X button at x=%d y=%d w=%d h=%d", card.x, card.y, card.w, card.h, b.x, b.y, b.w, b.h))
        check("the X is in the right half of the card", b.x + b.w / 2 > card.x + card.w / 2)
        check("the X is within the top fifth of the card", b.y + b.h / 2 < card.y + card.h / 5)
        check("the X is inside the card", b.x >= card.x and b.x + b.w <= card.x + card.w and b.y >= card.y)
        check("the X has a tap action", type(x_button.callback) == "function")
    end
    check("the card is on screen before the X is used", (function()
        for _i, w in ipairs(UIManager._window_stack) do if w.widget == shown then return true end end
        return false
    end)())
    -- the X's own action, not a tap anywhere (which closes the card as well)
    if x_button and type(x_button.callback) == "function" then
        x_button.callback()
        UIManager:forceRePaint()
        check("the X's action closes the card", (function()
            for _i, w in ipairs(UIManager._window_stack) do if w.widget == shown then return false end end
            return true
        end)())
        -- show it again: the rest of the test (screenshot) needs the card on screen
        real_show(UIManager, shown)
        UIManager:forceRePaint()
    end
end

-- the card is drawn over the page: save what it looks like
Screen:shot((os.getenv("SHOT_DIR") or ".") .. "/page_with_card.png")
print("saved page_with_card.png")

-- the same through KOReader's own dispatcher, as a gesture or a profile would run it. Events reach only the
-- topmost window, so the card is closed first (a gesture cannot fire while it is open either). The
-- dispatcher offers an action only while a reader is open, so a reader instance is put in place.
UIManager:close(shown)
UIManager:forceRePaint()
local ReaderUI = require("apps/reader/readerui")
ReaderUI.instance = ui -- ui.rolling is set and ui.paging is not: a book that reflows
shown, events_seen = nil, {}
Dispatcher:execute({ wordcount_page = true })
UIManager:forceRePaint()
check("the dispatcher sent the plugin's event", events_seen[1] == "onWordcountPage", tostring(events_seen[1]))
check("and the card was shown", shown ~= nil)
UIManager:close(shown)
UIManager:forceRePaint()
-- in a PDF (paging) and in the file manager the action must not run
for _i, context in ipairs({ "paging", "file manager" }) do
    ReaderUI.instance = context == "paging" and { paging = {} } or nil
    shown, events_seen = nil, {}
    Dispatcher:execute({ wordcount_page = true })
    check("not offered in " .. context, events_seen[1] == nil and shown == nil)
end
ReaderUI.instance = ui
-- the handler itself
shown = nil
check("the action handler says it handled the event", plugin:onWordcountPage() == true)
check("and shows the card", shown ~= nil)

if failures > 0 then print(failures .. " FAILURE(S)"); os.exit(1) end
print("all checks passed")
os.exit(0)
