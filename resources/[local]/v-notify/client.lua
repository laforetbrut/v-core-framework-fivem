-- v-notify | client
-- Themed toast notifications. Used by v-core Core.Notify and any module:
--   exports['v-notify']:show({ type = 'success', title = 'Bank', message = '...', duration = 4000 })

local function show(data)
    if type(data) ~= 'table' then data = { message = tostring(data) } end
    SendNUIMessage({
        action   = 'notify',
        type     = data.type or 'info',        -- info | success | error | warning
        title    = data.title or false,
        message  = data.message or '',
        duration = data.duration or 4000,
    })
end

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
