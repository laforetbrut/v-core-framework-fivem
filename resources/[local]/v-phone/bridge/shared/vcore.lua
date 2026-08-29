-- v-phone | bridge/shared/vcore.lua
--
-- **The v-core branch.** Added for this framework; nothing else in the resource is changed.
--
-- This phone is written against a library called `V`, and ships two of them. `bridge/shared/v.lua`
-- is the standalone one: it reads settings out of `Config.Settings` and lets a convar override
-- them, because a resource running on qb-core or on nothing at all has no admin panel to ask.
-- v-core has one, and its own `@v-core/lib/v.lua` is loaded straight after the standalone file
-- in the manifest, so the twenty-nine functions the two share come from the framework and the
-- six the bridge adds on top survive. The phone's own call sites never change, which is the
-- whole point of the API having been kept identical.
--
-- WHAT THIS FILE IS FOR. One seam is left after that swap. v-core's `V.Setting` answers with the
-- operator's value or the caller's default, and knows nothing about `Config.Settings` sitting
-- between them. Nearly every call in the phone passes a default already - 48 of the 49 - but they
-- pass it from `Config.Battery`, `Config.NumberFormat` and the rest, not from `Config.Settings`.
-- So a server that had edited `Config.Settings` in the file would have had those edits quietly
-- ignored the moment the panel took over.
--
-- Three places are asked, nearest first: what the operator set in the panel, then what the file
-- says, then what the caller passed. Nobody's configuration is lost by moving to v-core.

if not V or not V.Setting then return end

local coreSetting = V.Setting

--- The panel, then Config.Settings, then the caller's default.
function V.Setting(key, default)
    local fromPanel = coreSetting(key, nil)
    if fromPanel ~= nil then return fromPanel end

    local settings = Config and Config.Settings
    local fromFile = settings and settings[key]
    if fromFile ~= nil then return fromFile end

    return default
end

-- SettingBool and SettingNumber in v-core's library both call V.Setting through the module
-- table, so they pick this up without being wrapped themselves. Redefining them here would
-- take a copy of the old one and undo the line above.
