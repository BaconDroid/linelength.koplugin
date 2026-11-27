-- The settings of the plugin: what the auto-tune does, kept in KOReader's own settings file so it
-- follows the reader from one device to another.
local Settings = {}

-- The defaults: the auto-tune is off until it is asked for, the line length has to land between 56
-- and 60 characters and to reach 58, and the margins stay between the bounds the reader set. The size
-- of the text is never touched: it is the reader's own.
Settings.DEFAULTS = {
    enabled = false,
    band_min = 56,
    band_max = 60,
    target = 58,
    margin_min = 10,
    margin_max = 50,
    max_chars_per_step = 6,
    sample_first = 0,
    sample_middle = 6,
    sample_last = 0,
    max_steps = 6,
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
