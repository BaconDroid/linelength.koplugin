package.path = "./?.lua;" .. package.path

local failures = 0
local function expect(name, got, want)
    if got ~= want then
        failures = failures + 1
        print(string.format("FAIL %s: got %q, want %q", name, tostring(got), tostring(want)))
    end
end

-- The file of settings, as KOReader keeps it: a table of settings, read and written.
local stored = {}
package.loaded["datastorage"] = nil
package.preload["datastorage"] = function()
    return {
        getSettingsDir = function() return "/tmp/linelength-tests" end,
    }
end
package.preload["luasettings"] = function()
    return {
        open = function()
            return {
                readSetting = function(_self, _key, _default) return stored.settings or {} end,
                writeSetting = function(_self, _key, value) stored.settings = value end,
                flush = function() return true end,
            }
        end,
    }
end

local Settings = require("linelength/settings")

expect("the auto-tune is off by default", Settings:read().enabled, false)
expect("the margins start at 10", Settings:read().margin_min, 10)
expect("the margins end at 50", Settings:read().margin_max, 50)

-- The band, the target and the sample are the auto-tune's own: they are not settings.
expect("the band is not a setting", Settings:read().band_min, nil)
expect("the target is not a setting", Settings:read().target, nil)
expect("the sample is not a setting", Settings:read().sample_middle, nil)

-- The settings are written back as they were read, so a change the reader makes is kept.
local settings = Settings:read()
settings.enabled = true
Settings:write(settings)
expect("the settings are kept", Settings:read().enabled, true)
expect("and the numbers with them", Settings:read().margin_max, 50)

-- The file is a plain Lua table, so a number written as a string stays a string. Lua refuses to
-- compare a string with a number, and the menu compares the numbers it reads, so the numbers are
-- taken back as numbers when they are read.
stored.settings = { enabled = true, margin_min = "10", margin_max = "50" }
local from_strings = Settings:read()
expect("a number written as a string comes back as a number", type(from_strings.margin_min), "number")
expect("a number written as a string comes back as a number", type(from_strings.margin_max), "number")
expect("and it is the number it was", from_strings.margin_min, 10)
expect("and it is the number it was", from_strings.margin_max, 50)

-- A value that is not a number at all falls back to the default, rather than reaching the loop.
stored.settings = { margin_max = "not a number" }
expect("a value that is not a number falls back", Settings:read().margin_max, 50)

-- The settings that are read are the ones the plugin knows: a file that holds something else keeps
-- its own keys, and the plugin writes back the ones it read.
stored.settings = { margin_min = 20, margin_max = 60 }
local with_stored = Settings:read()
expect("the settings that were stored are read back", with_stored.margin_max, 60)
expect("the settings that were stored are read back", with_stored.margin_min, 20)
expect("and the ones that were not stored come from the defaults", with_stored.enabled, false)

-- The settings file is a plain Lua table, so the whole of what sits under the key can be written
-- wrong: a value that is not a table falls back to the defaults rather than raising.
stored.settings = 42
local from_number = Settings:read()
expect("the settings that are not a table fall back", from_number.enabled, false)
expect("the settings that are not a table fall back", from_number.margin_min, 10)
expect("the settings that are not a table fall back", from_number.margin_max, 50)

stored.settings = "nope"
expect("the settings that are not a table fall back", Settings:read().margin_min, 10)

if failures > 0 then
    error(failures .. " settings test(s) failed")
end
print("settings: all tests passed")
