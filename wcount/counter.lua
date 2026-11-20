-- Counting for the Word count plugin. Pure Lua: no KOReader requires, so it is tested on a
-- desktop Lua. LuaJIT/Lua 5.1 safe (no goto, no bit operators).
--
-- A "character" is one Unicode code point, so "é" is 1, not 2 bytes. Invisible formatting
-- characters (soft hyphen, zero-width space and joiners, direction marks, BOM) are not counted
-- and do not split words. A "word" is a run of characters between spaces that holds at least one
-- character that is not punctuation, so a lone dash or "..." is not a word.
local Counter = {}

-- Decode UTF-8 to code points. Anything that is not valid UTF-8 becomes U+FFFD, one per bad byte.
local function decode(s)
    local cps, n, i = {}, #s, 1
    local count = 0
    while i <= n do
        local c = s:byte(i)
        local cp, len
        if c < 0x80 then
            cp, len = c, 1
        elseif c >= 0xC2 and c <= 0xDF then
            cp, len = c - 0xC0, 2
        elseif c >= 0xE0 and c <= 0xEF then
            cp, len = c - 0xE0, 3
        elseif c >= 0xF0 and c <= 0xF4 then
            cp, len = c - 0xF0, 4
        else
            cp, len = 0xFFFD, 1
        end
        if len > 1 then
            for k = 1, len - 1 do
                local b = s:byte(i + k)
                if not b or b < 0x80 or b > 0xBF then
                    cp, len = 0xFFFD, 1
                    break
                end
                cp = cp * 64 + (b - 0x80)
            end
        end
        count = count + 1
        cps[count] = cp
        i = i + len
    end
    return cps
end

local SPACES = {
    [9] = true, [10] = true, [11] = true, [12] = true, [13] = true, [32] = true,
    [0x85] = true, [0xA0] = true, [0x1680] = true, [0x2028] = true, [0x2029] = true,
    [0x202F] = true, [0x205F] = true, [0x3000] = true,
}

local function isSpace(cp)
    return SPACES[cp] == true or (cp >= 0x2000 and cp <= 0x200A)
end

local function isInvisible(cp)
    return cp == 0xAD or cp == 0xFEFF
        or (cp >= 0x200B and cp <= 0x200F)
        or (cp >= 0x202A and cp <= 0x202E)
        or (cp >= 0x2060 and cp <= 0x2064)
end

local PUNCT = { [0xA1] = true, [0xA7] = true, [0xAB] = true, [0xB6] = true, [0xB7] = true,
                [0xBB] = true, [0xBF] = true }

local function isPunct(cp)
    if cp < 0x80 then
        return (cp >= 33 and cp <= 47) or (cp >= 58 and cp <= 64)
            or (cp >= 91 and cp <= 96) or (cp >= 123 and cp <= 126)
    end
    return PUNCT[cp] == true
        or (cp >= 0x2010 and cp <= 0x2027)
        or (cp >= 0x2030 and cp <= 0x205E)
        or (cp >= 0x3001 and cp <= 0x3003)
        or (cp >= 0x3008 and cp <= 0x3011)
end

--- Count a string.
-- @param text string (nil or non-string counts as empty)
-- @return table { words, chars, chars_no_spaces }; chars includes spaces and line breaks
function Counter.count(text)
    local res = { words = 0, chars = 0, chars_no_spaces = 0 }
    if type(text) ~= "string" or text == "" then
        return res
    end
    local in_token, token_is_word = false, false
    local cps = decode(text)
    for i = 1, #cps do
        local cp = cps[i]
        if isInvisible(cp) then
            -- not a character, and it does not end a word: nothing to do
        elseif isSpace(cp) then
            res.chars = res.chars + 1
            if in_token and token_is_word then
                res.words = res.words + 1
            end
            in_token, token_is_word = false, false
        else
            res.chars = res.chars + 1
            res.chars_no_spaces = res.chars_no_spaces + 1
            in_token = true
            if not isPunct(cp) then
                token_is_word = true
            end
        end
    end
    if in_token and token_is_word then
        res.words = res.words + 1
    end
    return res
end

return Counter
