-- Unit tests for wcount/counter.lua. Run through tests/run.py (lupa), not on the device.
package.path = "./?.lua;" .. package.path
local Counter = require("wcount/counter")

local failures = 0
local function check(name, text, words, chars, no_spaces)
    local r = Counter.count(text)
    local ok = r.words == words and r.chars == chars and r.chars_no_spaces == no_spaces
    if not ok then
        failures = failures + 1
        print(string.format("FAIL %s: got words=%d chars=%d nospace=%d, want %d/%d/%d",
            name, r.words, r.chars, r.chars_no_spaces, words, chars, no_spaces))
    end
end

check("empty", "", 0, 0, 0)
check("nil", nil, 0, 0, 0)
check("number is not text", 42, 0, 0, 0)
check("two words", "hello world", 2, 11, 10)
check("spaces count", " ", 0, 1, 0)
check("repeated spaces are chars", "a  b", 2, 4, 2)
check("newline is a char and a separator", "one\ntwo", 2, 7, 6)
check("contraction is one word", "don't", 1, 5, 5)
check("quotes and commas stay attached", "\226\128\156Hello,\226\128\157 she said.", 3, 18, 16)
check("dash alone is not a word", "a \226\128\148 b", 2, 5, 3)
check("em dash joins when unspaced", "stop\226\128\148go", 1, 7, 7)
check("ellipsis alone is not a word", "wait ...", 1, 8, 7)
check("ellipsis character alone", "wait \226\128\166", 1, 6, 5)
check("numbers are words", "3.14 and 42", 3, 11, 9)
check("hyphenated is one word", "well-known", 1, 10, 10)
-- UTF-8: characters, not bytes
check("accents", "Caf\195\169 \195\177and\195\186", 2, 10, 9)
check("emoji is one char", "a\240\159\152\128b", 1, 3, 3)
check("cjk counted by spaces only", "\230\151\165\230\156\172\232\170\158 \227\131\134\227\130\185\227\131\136", 2, 7, 6)
-- spaces other than U+0020
check("no-break space separates", "a\194\160b", 2, 3, 2)
check("ideographic space separates", "a\227\128\128b", 2, 3, 2)
check("thin space separates", "a\226\128\137b", 2, 3, 2)
-- invisible characters are not counted and do not split a word
check("zero-width space", "ab\226\128\139cd", 1, 4, 4)
check("soft hyphen", "hy\194\173phen", 1, 6, 6)
check("bom at start", "\239\187\191hi", 1, 2, 2)
-- bad UTF-8 must not crash, each bad byte is one character
check("invalid byte", "a\255b", 1, 3, 3)
check("truncated sequence", "ab\226\128", 1, 4, 4)

-- a long selection stays fast and exact
local big = string.rep("word ", 50000)
local r = Counter.count(big)
if r.words ~= 50000 or r.chars ~= 250000 then
    failures = failures + 1
    print("FAIL long text", r.words, r.chars)
end

if failures > 0 then
    error(failures .. " counter test(s) failed")
end
print("counter: all tests passed")
