-- v-notify | client
-- Themed toast notifications. Used by v-core Core.Notify and any module:
--   exports['v-notify']:show({ type = 'success', title = 'Bank', message = '...', duration = 4000 })

--[[
    Both values are read on every toast rather than cached at start-up. This module is
    ensured BEFORE v-core - Core.Notify needs it to exist - so anything read once here would
    be read before the core could answer, and the operator's values would never apply.
    V.Setting returns the fallback while the core is still coming up, so early toasts still
    look right and later ones pick up whatever the panel says.
]]
local function show(data)
    if type(data) ~= 'table' then data = { message = tostring(data) } end
    SendNUIMessage({
        action   = 'notify',
        type     = data.type or 'info',        -- info | success | error | warning
        title    = data.title or false,
        message  = data.message or '',
        -- A caller that asked for a duration gets it; everything else follows the operator.
        duration = data.duration or V.SettingNumber('duration', 4000),
        maxStack = V.SettingNumber('maxStack', 4),
    })
end

-- `Show` is the framework convention (every other export is PascalCase); `show` stays
-- for anything already calling it. Being the one lowercase export in ~60 is exactly the
-- kind of detail that costs an integrator half an hour.
exports('Show', show)
exports('show', show)

RegisterNetEvent('v-notify:show', function(data)
    show(data)
end)

-- ── Theme ──────────────────────────────────────────────────────
-- A NUI page can only be messaged by the resource that owns it, so v-ui cannot reach this
-- one directly: it publishes a version and each module forwards it into its own page.
local function pushTheme()
    if GetResourceState('v-ui') ~= 'started' then return end
    SendNUIMessage({ action = 'v-ui:theme', version = exports['v-ui']:Version() })
end

AddEventHandler('v-ui:client:themeChanged', function() pushTheme() end)
CreateThread(function() Wait(4000); pushTheme() end)
