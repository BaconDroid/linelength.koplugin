-- The settings of the plugin: what the reader chooses, kept in KOReader's own settings file so it
-- follows the reader from one device to another.
--
-- There are three of them: whether the auto-tune runs when a book opens, and how far the margins may
-- go. The rest of the auto-tune is its own: the band of line lengths and the target inside it, the
-- size of a step and the number of steps at most are the constants of linelength/autotune.lua, and the
-- pages that are measured are the constants of linelength/sample.lua.
local Settings = {}

-- The defaults: the auto-tune is off until it is asked for, and the margins stay between the bounds the
-- reader set. The band, the target, the sample and the step size are the auto-tune's own constants, in
-- linelength/autotune.lua and linelength/sample.lua.
Settings.DEFAULTS = {
    enabled = false,
    margin_min = 10,
    margin_max = 50,
}

local DataStorage = require("datastorage")
local LuaSettings = require("luasettings")

function Settings:read()
    if not self.settings_obj then
        self.settings_obj = LuaSettings:open(DataStorage:getSettingsDir() .. "/linelength.lua")
    end
    local stored = self.settings_obj:readSetting("settings", {})
    -- The settings file is a plain Lua table the reader can edit by hand, so what sits under the key
    -- can be anything: a value that is not a table falls back to the defaults rather than raising.
    if type(stored) ~= "table" then
        stored = {}
    end
    local settings = {}
    for key, value in pairs(Settings.DEFAULTS) do
        settings[key] = stored[key]
        if settings[key] == nil then
            settings[key] = value
        elseif type(value) == "number" then
            -- The settings file is a plain Lua table, so a number written as a string stays a string, and
            -- Lua refuses to compare a string with a number. The number is taken back here, once, for
            -- everything that reads the settings.
            settings[key] = tonumber(settings[key]) or value
        end
    end
    return settings
end

function Settings:write(settings)
    if not self.settings_obj then
        self.settings_obj = LuaSettings:open(DataStorage:getSettingsDir() .. "/linelength.lua")
    end
    self.settings_obj:writeSetting("settings", settings)
    self.settings_obj:flush()
end

return Settings
