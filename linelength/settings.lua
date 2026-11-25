-- The settings of the plugin: what the auto-tune does, kept in KOReader's own settings file so it
-- follows the reader from one device to another.
local Settings = {}

-- The defaults: the auto-tune is off until it is asked for, the line length has to land in the band the
-- plugin calls Excellent (50 to 66 characters), and the text size and the margins stay in the range
-- where a line of that length is possible on a screen like a Kobo's.
Settings.DEFAULTS = {
    enabled = false,
    band_min = 50,
    band_max = 66,
    target = 60,
    font_min = 20,
    font_max = 27,
    margin_min = 10,
    margin_max = 60,
    sample_first = 0,
    sample_middle = 6,
    sample_last = 0,
    max_steps = 4,
}

local DataStorage = require("datastorage")
local LuaSettings = require("luasettings")

function Settings:read()
    if not self.settings_obj then
        self.settings_obj = LuaSettings:open(DataStorage:getSettingsDir() .. "/linelength.lua")
    end
    local stored = self.settings_obj:readSetting("settings", {})
    local settings = {}
    for key, value in pairs(Settings.DEFAULTS) do
        settings[key] = stored[key]
        if settings[key] == nil then
            settings[key] = value
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
