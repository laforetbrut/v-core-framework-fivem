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

    -- Resolve permission: DB value, upgraded by any config bootstrap admin.
    local perm = VCore.DB.GetUserPermission(license)
    local bootstrap = Config.Admins[license]
    if bootstrap and VCore.PermRank(bootstrap) > VCore.PermRank(perm) then
        perm = bootstrap
        VCore.DB.SetUserPermission(license, perm)
    end
    player.permission = perm

    VCore.Players[src] = player

    VCore.Debug(('player loaded: %s [%s] (id %s, %s)'):format(player.name, player.citizenid, src, perm))
    VCore.Log('connect', ('%s connected'):format(player.name), { source = src }, player.citizenid)
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

-- ── Admin commands (permission-gated; players never type commands) ──
-- /givemoney <id> <cash|bank> <amount>
RegisterCommand('givemoney', function(source, args)
    if source ~= 0 and not VCore.HasPermission(source, 'admin') then return end
    local target = tonumber(args[1])
    local account = args[2] or 'cash'
    local amount = tonumber(args[3])
    local player = target and VCore.GetPlayer(target)
    if not player or not amount then return end
    if player.AddMoney(account, amount, 'admin-give') then
        VCore.Log('economy', ('admin gave $%d %s to %s'):format(amount, account, player.citizenid),
            { by = source }, player.citizenid)
    end
end, false)

-- /setperm <id> <user|mod|admin|superadmin>
RegisterCommand('setperm', function(source, args)
    if source ~= 0 and not VCore.HasPermission(source, 'superadmin') then return end
    local target = tonumber(args[1])
    local level = args[2]
    if target and level and VCore.SetPermission(target, level) then
        VCore.Log('admin', ('permission of %d set to %s'):format(target, level), { by = source })
    end
end, false)

CreateThread(function()
    VCore.Debug(('server core ready (v%s)'):format(VCore.Version))
end)
