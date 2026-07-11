-- v-admin | server
local Core = exports['v-core']:GetCore()
local startedAt = os.time()

local function isAdmin(src) local p = Core.GetPlayer(src); return p and p.HasPermission(Config.Permission) end
local function isSuper(src) local p = Core.GetPlayer(src); return p and p.HasPermission('superadmin') end

local function listedResource(name)
    for _, pre in ipairs(Config.ResourcePrefixes) do
        if name:sub(1, #pre) == pre then return true end
    end
    return false
end

-- ── Panel bootstrap ────────────────────────────────────────────
Core.RegisterCallback('v-admin:open', function(source, resolve)
    if not isAdmin(source) then resolve(false); return end
    resolve({ ok = true, super = isSuper(source), weathers = Config.Weathers })
end)

Core.RegisterCallback('v-admin:dashboard', function(source, resolve)
    if not isAdmin(source) then resolve(false); return end
    local players = 0
    for _ in pairs(Core.Players) do players = players + 1 end
    local resources, running = 0, 0
    for i = 0, GetNumResources() - 1 do
        local n = GetResourceByFindIndex(i)
        if n and listedResource(n) then
            resources = resources + 1
            if GetResourceState(n) == 'started' then running = running + 1 end
        end
    end
    local chars = MySQL.scalar.await('SELECT COUNT(*) FROM characters') or 0
    resolve({
        uptime = os.time() - startedAt, players = players, maxPlayers = GetConvarInt('sv_maxclients', 48),
        resources = resources, running = running, characters = chars,
    })
end)

Core.RegisterCallback('v-admin:players', function(source, resolve)
    if not isAdmin(source) then resolve(false); return end
    local list = {}
    for src, p in pairs(Core.Players) do
        list[#list + 1] = {
            id = src, name = p.charinfo and (p.charinfo.firstname .. ' ' .. p.charinfo.lastname) or p.name,
            account = GetPlayerName(src), citizenid = p.citizenid,
            job = p.job and p.job.name or 'unemployed',
            cash = p.money and p.money.cash or 0, bank = p.money and p.money.bank or 0,
            ping = GetPlayerPing(src), permission = p.permission or 'user',
        }
    end
    table.sort(list, function(a, b) return a.id < b.id end)
    resolve(list)
end)

Core.RegisterCallback('v-admin:resources', function(source, resolve)
    if not isAdmin(source) then resolve(false); return end
    local list = {}
    for i = 0, GetNumResources() - 1 do
        local n = GetResourceByFindIndex(i)
        if n and listedResource(n) then
            list[#list + 1] = { name = n, state = GetResourceState(n), protected = Config.ProtectedResources[n] or false }
        end
    end
    table.sort(list, function(a, b) return a.name < b.name end)
    resolve(list)
end)

Core.RegisterCallback('v-admin:logs', function(source, resolve, filter)
    if not isAdmin(source) then resolve(false); return end
    local rows
    if filter and filter ~= '' then
        rows = MySQL.query.await('SELECT category, message, citizenid, created_at FROM logs WHERE category = ? ORDER BY id DESC LIMIT 60', { filter })
    else
        rows = MySQL.query.await('SELECT category, message, citizenid, created_at FROM logs ORDER BY id DESC LIMIT 60')
    end
    resolve(rows or {})
end)

-- ── Actions ────────────────────────────────────────────────────
local Actions = {}

function Actions.kick(src, d)
    local target = tonumber(d.target); if not target or not Core.Players[target] then return false end
    DropPlayer(target, d.reason and ('Kick: ' .. d.reason) or 'Kicked by an administrator')
    return true, ('kicked %d (%s)'):format(target, d.reason or '-')
end

function Actions.heal(src, d)
    local target = tonumber(d.target); if not target or not Core.Players[target] then return false end
    TriggerClientEvent('v-admin:client:heal', target)
    return true, ('healed %d'):format(target)
end

function Actions.freeze(src, d)
    local target = tonumber(d.target); if not target or not Core.Players[target] then return false end
    TriggerClientEvent('v-admin:client:freeze', target, d.state and true or false)
    return true, ('%s %d'):format(d.state and 'froze' or 'unfroze', target)
end

function Actions.bring(src, d)
    local target = tonumber(d.target); if not target or not Core.Players[target] then return false end
    local c = GetEntityCoords(GetPlayerPed(src))
    TriggerClientEvent('v-admin:client:teleport', target, c.x, c.y, c.z)
    return true, ('brought %d'):format(target)
end

Actions['goto'] = function(src, d)
    local target = tonumber(d.target); if not target or not Core.Players[target] then return false end
    local c = GetEntityCoords(GetPlayerPed(target))
    TriggerClientEvent('v-admin:client:teleport', src, c.x, c.y, c.z)
    return true, ('went to %d'):format(target)
end

function Actions.money(src, d)
    local target = tonumber(d.target); local player = target and Core.GetPlayer(target)
    local amount = math.floor(tonumber(d.amount) or 0)
    local account = (d.account == 'bank') and 'bank' or 'cash'
    if not player or amount == 0 then return false end
    local ok
    if amount > 0 then ok = player.AddMoney(account, amount, 'admin-panel')
    else ok = player.RemoveMoney(account, -amount, 'admin-panel') end
    return ok, ('%s $%d %s -> %s'):format(amount > 0 and 'gave' or 'took', math.abs(amount), account, player.citizenid)
end

function Actions.setperm(src, d)
    local target = tonumber(d.target)
    local levels = { user = true, mod = true, admin = true, superadmin = true }
    if not target or not levels[d.level or ''] then return false end
    if not Core.SetPermission(target, d.level) then return false end
    -- Demoted below admin: revoke their client-side self-tools (noclip / god / etc.)
    if d.level ~= 'admin' and d.level ~= 'superadmin' then
        TriggerClientEvent('v-admin:client:revoke', target)
    end
    return true, ('permission of %d -> %s'):format(target, d.level)
end

function Actions.giveitem(src, d)
    local target = tonumber(d.target)
    local count = math.max(1, math.floor(tonumber(d.count) or 1))
    local item = tostring(d.item or ''):lower():gsub('[^%w_%-]', '')
    if not target or not Core.Players[target] or item == '' then return false end
    if GetResourceState('v-inventory') ~= 'started' then return false end
    local ok = exports['v-inventory']:AddItem(target, item, count)
    return ok and true or false, ('gave %dx %s to %d'):format(count, item, target)
end

function Actions.car(src, d)
    local model = tostring(d.model or ''):lower():gsub('[^%w_]', '')
    if model == '' then return false end
    TriggerClientEvent('v-admin:client:car', src, model)
    return true, ('spawned vehicle %s'):format(model)
end

function Actions.weather(src, d)
    local w = tostring(d.value or ''):upper()
    local ok = false
    for _, v in ipairs(Config.Weathers) do if v == w then ok = true; break end end
    if not ok then return false end
    GlobalState.vweather = w
    TriggerClientEvent('v-admin:client:weather', -1, w)
    return true, ('weather -> %s'):format(w)
end

function Actions.time(src, d)
    local h = math.floor(tonumber(d.hour) or 12) % 24
    local freeze = d.freeze and true or false
    GlobalState.vtime = { h = h, freeze = freeze }
    TriggerClientEvent('v-admin:client:time', -1, h, freeze)
    return true, ('time -> %02d:00%s'):format(h, freeze and ' (frozen)' or '')
end

function Actions.announce(src, d)
    local msg = tostring(d.message or ''):sub(1, 220)
    if msg == '' then return false end
    TriggerClientEvent('v-notify:show', -1, { type = 'warning', title = 'PROJET R', message = msg, duration = 9000 })
    return true, ('announce: %s'):format(msg)
end

function Actions.resource(src, d)
    local verbs = { restart = true, stop = true, ensure = true }
    local verb = tostring(d.verb or '')
    local name = tostring(d.name or ''):gsub('[^%w_%-]', '')
    if not verbs[verb] or name == '' or not listedResource(name) then return false end
    if Config.ProtectedResources[name] and verb ~= 'ensure' then return false end
    ExecuteCommand(('%s %s'):format(verb, name))
    return true, ('%s %s'):format(verb, name)
end

Actions.spectate = function(src, d)
    local target = tonumber(d.target); if not target or not Core.Players[target] then return false end
    local tped = GetPlayerPed(target)
    if not tped or tped == 0 then return false end
    local c = GetEntityCoords(tped)
    TriggerClientEvent('v-admin:client:spectate', src, c.x, c.y, c.z, target)
    return true, ('spectate %d'):format(target)
end

-- ── Player ESP: stream every player's position to admins who enabled it ────
local EspOn = {}   -- [adminSrc] = true

RegisterNetEvent('v-admin:server:esp', function(on)
    local src = source
    if not isAdmin(src) then return end
    EspOn[src] = on and true or nil
end)

CreateThread(function()
    while true do
        Wait(1500)
        local any = false
        for _ in pairs(EspOn) do any = true; break end
        if any then
            local list = {}
            for sid, p in pairs(Core.Players) do
                local ped = GetPlayerPed(sid)
                if ped and ped ~= 0 then
                    local c = GetEntityCoords(ped)
                    list[#list + 1] = {
                        id = sid,
                        name = (p.charinfo and (p.charinfo.firstname .. ' ' .. p.charinfo.lastname)) or p.name or '?',
                        x = c.x, y = c.y, z = c.z,
                    }
                end
            end
            for adminSrc in pairs(EspOn) do
                if isAdmin(adminSrc) then
                    TriggerClientEvent('v-admin:client:positions', adminSrc, list)
                else
                    EspOn[adminSrc] = nil
                end
            end
        end
    end
end)

AddEventHandler('playerDropped', function() EspOn[source] = nil end)

Core.RegisterCallback('v-admin:action', function(source, resolve, d)
    if type(d) ~= 'table' or type(d.type) ~= 'string' then resolve(false); return end
    if not isAdmin(source) then resolve(false); return end
    if Config.SuperActions[d.type] and not isSuper(source) then resolve(false); return end
    local fn = Actions[d.type]
    if not fn then resolve(false); return end
    local ok, detail = fn(source, d)
    local admin = Core.GetPlayer(source)
    if ok then
        Core.Log('admin', ('[panel] %s: %s'):format(d.type, detail or ''), { by = source }, admin and admin.citizenid or '')
    end
    resolve(ok and true or false)
end)
