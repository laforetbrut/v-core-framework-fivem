-- v-core | client bootstrap
VCore = VCore or {}

-- Expose the core to other client resources:  local Core = exports['v-core']:GetCore()
exports('GetCore', function() return VCore end)

-- Tell the server we are ready the first time we spawn.
local hasLoaded = false
AddEventHandler('playerSpawned', function()
    if hasLoaded then return end
    hasLoaded = true
    TriggerServerEvent('v-core:server:playerReady')
end)

-- Server-driven notifications.
RegisterNetEvent('v-core:client:notify', function(message)
    VCore.Notify(message)
end)

CreateThread(function()
    VCore.Debug(('client core ready (v%s)'):format(VCore.Version))
end)
