-- v-core | server bootstrap & lifecycle
VCore = VCore or {}

-- Expose the core to every other server resource:
--   local Core = exports['v-core']:GetCore()
exports('GetCore', function() return VCore end)

-- ── Player load ────────────────────────────────────────────────
RegisterNetEvent('v-core:server:playerReady', function()
    local src = source
    if VCore.Players[src] then return end

    local license = VCore.GetLicense(src)
    if not license then
        DropPlayer(src, 'v-core: no license identifier found.')
        return
    end

    VCore.DB.EnsureUser(license, GetPlayerName(src))

    local row = VCore.DB.GetCharacterByLicense(license)
    if not row then
        row = VCore.DB.CreateDefaultCharacter(license, GetPlayerName(src))
    end

    local player = VCore.NewPlayer(src, row)
    VCore.Players[src] = player

    VCore.Debug(('player loaded: %s [%s] (id %s)'):format(player.name, player.citizenid, src))
    TriggerClientEvent('v-core:client:playerLoaded', src, player.ExportData())
    TriggerEvent('v-core:server:onPlayerLoaded', src, player)
end)

-- ── Player unload (save) ───────────────────────────────────────
AddEventHandler('playerDropped', function()
    local src = source
    local player = VCore.Players[src]
    if not player then return end
    player.Save()
    VCore.Debug(('player saved & dropped: %s (id %s)'):format(player.name, src))
    VCore.Players[src] = nil
end)

-- Save everyone when the resource stops (server restart / update).
AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for _, player in pairs(VCore.Players) do
        player.Save()
    end
end)

-- ── Autosave loop ──────────────────────────────────────────────
CreateThread(function()
    while true do
        Wait(Config.SaveInterval)
        local count = 0
        for _, player in pairs(VCore.Players) do
            player.Save()
            count = count + 1
        end
        if count > 0 then VCore.Debug(('autosaved %d player(s)'):format(count)) end
    end
end)

-- ── Default server callbacks ───────────────────────────────────
VCore.RegisterCallback('v-core:getPlayerData', function(source, resolve)
    local player = VCore.GetPlayer(source)
    resolve(player and player.ExportData() or nil)
end)

-- ── Demo command: /vmoney -> shows your balances ───────────────
RegisterCommand('vmoney', function(source)
    local player = VCore.GetPlayer(source)
    if not player then return end
    VCore.Notify(source, ('Cash: $%s  |  Bank: $%s'):format(
        VCore.FormatMoney(player.money.cash), VCore.FormatMoney(player.money.bank)), 'info')
end, false)

CreateThread(function()
    VCore.Debug(('server core ready (v%s)'):format(VCore.Version))
end)
