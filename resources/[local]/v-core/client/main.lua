-- v-core | client bootstrap & data sync
VCore = VCore or {}
VCore.PlayerData = {}
VCore.isLoaded   = false

-- Expose the core / player data to other client resources.
exports('GetCore', function() return VCore end)
exports('GetPlayerData', function() return VCore.PlayerData end)

-- Tell the server we are ready the first time we spawn.
local firstSpawn = true
AddEventHandler('playerSpawned', function()
    if not firstSpawn then return end
    firstSpawn = false
    TriggerServerEvent('v-core:server:playerReady')
end)

-- Full player data received from the server.
RegisterNetEvent('v-core:client:playerLoaded', function(data)
    VCore.PlayerData = data
    VCore.isLoaded   = true
    VCore.Debug(('loaded as %s [%s]'):format(data.name, data.citizenid))
    TriggerEvent('v-core:client:onPlayerLoaded', data)
end)

-- Live updates.
RegisterNetEvent('v-core:client:money', function(money, account, reason)
    VCore.PlayerData.money = money
    TriggerEvent('v-core:client:onMoneyChange', money, account, reason)
end)

RegisterNetEvent('v-core:client:job', function(job)
    VCore.PlayerData.job = job
    TriggerEvent('v-core:client:onJobChange', job)
end)

RegisterNetEvent('v-core:client:gang', function(gang)
    VCore.PlayerData.gang = gang
    TriggerEvent('v-core:client:onGangChange', gang)
end)

RegisterNetEvent('v-core:client:notify', function(message, kind, duration)
    VCore.Notify(message, kind, duration)
end)

CreateThread(function()
    VCore.Debug(('client core ready (v%s)'):format(VCore.Version))
end)
