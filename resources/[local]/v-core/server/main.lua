-- v-core | server bootstrap & lifecycle
VCore = VCore or {}

-- Expose the core to every other server resource:
--   local Core = exports['v-core']:GetCore()
exports('GetCore', function() return VCore end)

-- ── Player load ────────────────────────────────────────────────
local function loadPlayer(src, row, license)
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
    VCore.Notify(src, LP(src, 'core.welcome', Config.ServerName, player.name), 'info')
    TriggerClientEvent('v-core:client:playerLoaded', src, player.ExportData())
    TriggerEvent('v-core:server:onPlayerLoaded', src, player)
end
VCore.LoadPlayer = loadPlayer

RegisterNetEvent('v-core:server:playerReady', function()
    local src = source
    if VCore.Players[src] then return end

    local license = VCore.GetLicense(src)
    if not license then
        DropPlayer(src, 'v-core: no license identifier found.')
        return
    end

    VCore.DB.EnsureUser(license, GetPlayerName(src))
    local lang = VCore.DB.GetUserLanguage(license)
    Player(src).state:set('lang', lang, true)

    local row = VCore.DB.GetCharacterByLicense(license)
    if row then
        loadPlayer(src, row, license)
    else
        -- No character yet -> the client runs the creation flow (v-spawn).
        TriggerClientEvent('v-core:client:needCharacter', src, { language = lang })
    end
end)

-- Language selection (from v-spawn).
VCore.RegisterCallback('v-core:setLanguage', function(source, resolve, lang)
    lang = (lang == 'en') and 'en' or 'fr'
    local license = VCore.GetLicense(source)
    if license then VCore.DB.SetUserLanguage(license, lang) end
    Player(source).state:set('lang', lang, true)
    resolve(lang)
end)

-- Character creation (from v-spawn): identity + appearance -> create + load.
-- `creating` is a synchronous guard set BEFORE the first await, so a second
-- concurrent call (double-click / retry) can't race through the DB writes.
local creating = {}
VCore.RegisterCallback('v-core:createCharacter', function(source, resolve, data)
    local license = VCore.GetLicense(source)
    if not license or VCore.Players[source] or creating[source] then resolve(false); return end
    creating[source] = true

    local ok, row = pcall(VCore.DB.CreateCharacter, license, data or {})
    if not ok or not row then
        creating[source] = nil
        resolve(false)
        return
    end

    loadPlayer(source, row, license)
    creating[source] = nil
    resolve(true)
end)
VCore.Creating = creating

-- Persist appearance changes (barber / clothing stores later).
RegisterNetEvent('v-core:server:saveAppearance', function(appearance)
    local player = VCore.GetPlayer(source)
    if player then
        player.appearance = appearance
        VCore.DB.SaveAppearance(player.citizenid, appearance)
    end
end)

-- ── Player unload (save) ───────────────────────────────────────
AddEventHandler('playerDropped', function()
    local src = source
    if VCore.Creating then VCore.Creating[src] = nil end
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
