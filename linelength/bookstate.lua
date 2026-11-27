-- Whether a book has already been through the auto-tune, so that it is not measured again every time
-- it is opened. Pure Lua: no KOReader requires, so it is tested on a desktop Lua.
--
-- The flag is kept in the settings of the book itself (KOReader's own sidecar file), so it follows
-- the book to another device and is removed with it.
local BookState = {}

-- The key the flag is stored under, in the settings of the book.
BookState.KEY = "linelength_auto_tuned"

--- The settings of the book, or nil when they cannot be had (a document with no path, a settings
--- file that cannot be written).
--- @param ui table the reader
--- @return table|nil
function BookState.settings(ui)
    local doc = ui and ui.document
    local path = doc and doc.file
    if type(path) ~= "string" or path == "" then
        return nil
    end
    local ok, doc_settings = pcall(function()
        -- The settings of the book itself: KOReader keeps them in a sidecar file next to it, so they
        -- follow the book to another device. ui.doc_settings is the same thing when the reader has
        -- already opened them.
        if ui.doc_settings then
            return ui.doc_settings
        end
        local DocSettings = require("docsettings")
        return DocSettings:open(path)
    end)
    if not ok or not doc_settings then
        return nil
    end
    return doc_settings
end

--- Whether the book has already been tuned. A book whose settings cannot be read is treated as not
--- tuned: the tune then runs, and the flag is written next time.
--- @param ui table the reader
--- @return boolean
function BookState.wasTuned(ui)
    local doc_settings = BookState.settings(ui)
    if not doc_settings then
        return false
    end
    local ok, value = pcall(function()
        return doc_settings:readSetting(BookState.KEY)
    end)
    return ok and value == true
end

--- Remembers that the book has been tuned.
--- @param ui table the reader
--- @return boolean whether it was remembered
function BookState.markTuned(ui)
    local doc_settings = BookState.settings(ui)
    if not doc_settings then
        return false
    end
    local ok, value = pcall(function()
        doc_settings:saveSetting(BookState.KEY, true)
        -- The flush gives back where it wrote the settings, and nothing when the sidecar file could
        -- not be opened: the flag is then not on disk and the book would be tuned again.
        return doc_settings:flush()
    end)
    return ok == true and value ~= nil
end

--- Forgets that the book has been tuned, so that it is measured again.
--- @param ui table the reader
--- @return boolean whether it was forgotten
function BookState.clearTuned(ui)
    local doc_settings = BookState.settings(ui)
    if not doc_settings then
        return false
    end
    local ok, value = pcall(function()
        doc_settings:delSetting(BookState.KEY)
        -- As in markTuned: nothing comes back when the sidecar file could not be written.
        return doc_settings:flush()
    end)
    return ok == true and value ~= nil
end

return BookState
