-- dev-starter | server
-- Minimal QBCore server example. Duplicate this resource to start a new script.

local QBCore = exports['qb-core']:GetCoreObject()

-- /serverinfo — admin-only command that reports the online player count.
QBCore.Commands.Add('serverinfo', 'Show basic server info (dev demo)', {}, false, function(source)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end
    local online = #QBCore.Functions.GetPlayers()
    TriggerClientEvent('QBCore:Notify', src, ('Players online: %d'):format(online), 'primary')
end, 'admin')

print('^2[dev-starter]^7 server loaded — QBCore starter resource is running.')
