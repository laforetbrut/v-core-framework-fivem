-- v-ui | client
-- Forwards the theme version into THIS resource's NUI, and re-broadcasts it so every
-- other module can do the same for its own page (see exports below).
local themeVersion = 0

RegisterNetEvent('v-ui:client:theme', function(version)
    themeVersion = tonumber(version) or 0
    -- every module listens for this and pushes it into its own page
    TriggerEvent('v-ui:client:themeChanged', themeVersion)
end)

CreateThread(function()
    Wait(2000)
    TriggerServerEvent('v-ui:server:request')
end)

--- The current theme version. A module includes it in its NUI `open` payload so a page
--- that opens later still links the right stylesheet.
exports('Version', function() return themeVersion end)

--- One-liner for a module: push the theme into its own NUI right now.
--- Usage in any module's client, after SendNUIMessage({action='open', ...}):
---   exports['v-ui']:Push()
exports('Push', function()
    SendNUIMessage({ action = 'v-ui:theme', version = themeVersion })
end)
