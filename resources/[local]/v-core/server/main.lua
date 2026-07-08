-- v-core | server bootstrap
VCore = VCore or {}

-- Expose the core to other server resources:  local Core = exports['v-core']:GetCore()
exports('GetCore', function() return VCore end)

-- Load a player once the client reports it has spawned.
RegisterNetEvent('v-core:server:playerReady', function()
    local src = source
    if VCore.Players[src] then return end   -- already loaded

    local player = VCore.CreatePlayer(src)
    VCore.Players[src] = player

    VCore.Debug(('player loaded: %s (id %s)'):format(player.name, src))
    VCore.Notify(src, ('Welcome to %s, %s!'):format(Config.ServerName, player.name))
end)

-- Clean up on disconnect.
AddEventHandler('playerDropped', function()
    local src = source
    local player = VCore.Players[src]
    if player then
        VCore.Debug(('player dropped: %s (id %s)'):format(player.name, src))
        VCore.Players[src] = nil
    end
end)

-- Demo command proving the core works: /vmoney -> shows your balances.
RegisterCommand('vmoney', function(source)
    local player = VCore.GetPlayer(source)
    if not player then return end
    VCore.Notify(source, ('Cash: $%d  |  Bank: $%d'):format(player.money.cash, player.money.bank))
end, false)

CreateThread(function()
    VCore.Debug(('server core ready (v%s)'):format(VCore.Version))
end)
