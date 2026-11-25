-- Unit tests for linelength/bookstate.lua. Run through tests/run.py (lupa), not on the device.
package.path = "./?.lua;" .. package.path
local BookState = require("linelength/bookstate")

local failures = 0
local function expect(name, got, want)
    if got ~= want then
        failures = failures + 1
        print(string.format("FAIL %s: got %q, want %q", name, tostring(got), tostring(want)))
    end
end

-- The settings of a book, as KOReader keeps them: a table of settings that is read and written.
-- KOReader writes them to the sidecar file of the book and gives back where it wrote them, so a
-- successful flush has something to return.
local function fakeDocSettings(store)
    return {
        readSetting = function(_self, key)
            return store[key]
        end,
        saveSetting = function(_self, key, value) store[key] = value end,
        delSetting = function(_self, key) store[key] = nil end,
        flush = function() return true end,
    }
end

local function reader(store, opts)
    opts = opts or {}
    -- A book with no path at all is given the path false, which must stay false: the default path
    -- belongs to the books that have no path of their own to give.
    local path = opts.path
    if path == nil then
        path = "/books/a.epub"
    end
    local ui = { document = { file = path } }
    if not opts.no_settings and opts.path ~= false then
        ui.doc_settings = fakeDocSettings(store)
        if opts.flush_fails then
            -- A sidecar file that cannot be opened: the write never reaches the disk.
            ui.doc_settings.flush = function() end
        end
    end
    if opts.raising then
        ui.doc_settings = setmetatable({}, {
            __index = function() error("settings boom") end,
        })
    end
    return ui
end

expect("the key", BookState.KEY, "linelength_auto_tuned")

local store = {}
local ui = reader(store)
expect("a book that was not tuned", BookState.wasTuned(ui), false)
expect("marking it", BookState.markTuned(ui), true)
expect("the flag is in the settings of the book", store[BookState.KEY], true)
expect("a book that was tuned", BookState.wasTuned(ui), true)
expect("clearing it", BookState.clearTuned(ui), true)
expect("the flag is gone", store[BookState.KEY], nil)
expect("a book that was not tuned any more", BookState.wasTuned(ui), false)

local store_a, store_b = {}, {}
expect("the first book was not tuned", BookState.wasTuned(reader(store_a)), false)
BookState.markTuned(reader(store_a))
expect("the first book was tuned", BookState.wasTuned(reader(store_a)), true)
expect("the second book was not tuned", BookState.wasTuned(reader(store_b)), false)

expect("a book with no path has no settings", BookState.settings(reader({}, { path = false })), nil)
expect("a book with no path was not tuned", BookState.wasTuned(reader({}, { path = false })), false)
expect("and it cannot be marked", BookState.markTuned(reader({}, { path = false })), false)
expect("and it cannot be cleared", BookState.clearTuned(reader({}, { path = false })), false)

local raising = reader({}, { raising = true })
expect("a book whose settings fail reads as not tuned", BookState.wasTuned(raising), false)
expect("and marking it fails without raising", BookState.markTuned(raising), false)
expect("and clearing it fails without raising", BookState.clearTuned(raising), false)

-- The flag is only remembered when the sidecar file was written: a flush that gives nothing back
-- means the write did not reach the disk, and the book would be tuned again.
local written = {}
expect("marking a book whose settings can be written", BookState.markTuned(reader(written)), true)
expect("the flag is in the settings of the book", written[BookState.KEY], true)

local unwritten = reader({}, { flush_fails = true })
expect("a book whose settings cannot be written reads as not tuned", BookState.wasTuned(unwritten), false)
expect("marking it fails when the settings are not written", BookState.markTuned(unwritten), false)
expect("clearing it fails when the settings are not written", BookState.clearTuned(unwritten), false)

expect("no reader has no settings", BookState.settings(nil), nil)
expect("no reader was not tuned", BookState.wasTuned(nil), false)

if failures > 0 then
    error(failures .. " bookstate test(s) failed")
end
print("bookstate: all tests passed")
