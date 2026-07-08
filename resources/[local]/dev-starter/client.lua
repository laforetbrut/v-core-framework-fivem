-- dev-starter | client
-- Minimal QBCore client example. Duplicate this resource to start a new script.

local QBCore = exports['qb-core']:GetCoreObject()

-- /hello — greet the local player using their character data.
RegisterCommand('hello', function()
    local data = QBCore.Functions.GetPlayerData()
    local name = (data and data.charinfo and data.charinfo.firstname) or 'stranger'
    QBCore.Functions.Notify(('Hello %s — welcome to your dev server!'):format(name), 'success')
end, false)

-- Confirm load in the client console (F8).
CreateThread(function()
    print('[dev-starter] client loaded — try the /hello command in-game.')
end)
