-- v-garages | server
-- The only legitimate way an owned vehicle enters or leaves the world.
--
-- Everything is re-derived here: which garage the player is standing at (from the
-- server-owned ped), whether they may use it (job/gang lock), whether the plate is
-- theirs, and whether it is parked where they claim. The NUI is shown a list, but the
-- list it was shown is never trusted on the way back.
local Core = exports['v-core']:GetCore()

local Garages = Config.Garages   -- runtime list (DB, or config fallback)
local S = { OUT = 0, GARAGED = 1, IMPOUND = 2 }

local function rebuildGarages()
    local rows = (GetResourceState('v-world') == 'started' and exports['v-world']:IsReady())
        and exports['v-world']:GetGarages() or nil
    local list = {}
    for _, r in ipairs(rows or {}) do
        if r.enabled == 1 then list[#list + 1] = r end
    end
    if #list == 0 then list = Config.Garages end
    Garages = list
    TriggerClientEvent('v-garages:client:garages', -1, Garages)
end

local function garageById(id)
    for _, g in ipairs(Garages) do if g.id == id then return g end end
end

--- May `src` use this garage? Job/gang-locked garages check the real job, and the
--- player must be physically at the interaction point.
local function canUse(src, g)
    if not g then return false, 'unknown' end
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return false, 'far' end
    if #(GetEntityCoords(ped) - vector3(g.x + 0.0, g.y + 0.0, g.z + 0.0)) > (Config.Distance + 3.0) then
        return false, 'far'
    end
    if g.job and g.job ~= '' then
        local p = Core.GetPlayer(src)
        local job = p and p.job                       -- { name, grade }
        local gang = p and p.gang
        local ok = (job and job.name == g.job) or (g.type == 'gang' and gang and gang.name == g.job)
        if not ok then return false, 'nojob' end
    end
    return true
end

-- ── List what is parked here ───────────────────────────────────
Core.RegisterCallback('v-garages:list', function(source, resolve, data)
    local g = garageById(type(data) == 'table' and tostring(data.garage or '') or '')
    local ok, why = canUse(source, g)
    if not ok then resolve({ error = why }); return end
    local p = Core.GetPlayer(source)
    if not p then resolve(false); return end

    -- An impound lot shows every impounded car you own, wherever it was parked;
    -- a normal garage shows the cars parked in that specific garage.
    -- `props` rides along so the showroom preview dresses the car exactly as it is parked.
    local rows
    if g.type == 'impound' then
        rows = MySQL.query.await(
            'SELECT plate, model, fuel, engine, body, garage, props FROM character_vehicles WHERE citizenid = ? AND state = ?',
            { p.citizenid, S.IMPOUND }) or {}
    else
        rows = MySQL.query.await(
            'SELECT plate, model, fuel, engine, body, garage, props FROM character_vehicles WHERE citizenid = ? AND garage = ? AND state = ?',
            { p.citizenid, g.id, S.GARAGED }) or {}
    end
    for _, r in ipairs(rows) do
        if type(r.props) == 'string' then r.props = json.decode(r.props) or {} end
    end
    resolve({ garage = { id = g.id, label = g.label, type = g.type, fee = g.fee or 0 },
              rows = rows, cash = p.money.cash, bank = p.money.bank })
end)

-- ── Retrieve ───────────────────────────────────────────────────
Core.RegisterCallback('v-garages:take', function(source, resolve, data)
    if type(data) ~= 'table' then resolve(false); return end
    local g = garageById(tostring(data.garage or ''))
    local ok, why = canUse(source, g)
    if not ok then resolve({ error = why }); return end

    local p = Core.GetPlayer(source)
    local plate = tostring(data.plate or '')
    if not p or plate == '' then resolve(false); return end

    local row = exports['v-vehicles']:GetVehicle(plate)
    if not row or row.citizenid ~= p.citizenid then resolve({ error = 'notyours' }); return end
    if exports['v-vehicles']:IsLive(plate) then resolve({ error = 'already' }); return end

    -- Re-derive the parking state instead of trusting the list the NUI showed.
    -- Impound keeps its own per-lot fee; a public garage can charge a flat retrieval
    -- fee set once for the whole server.
    local fee
    if g.type == 'impound' then
        if row.state ~= S.IMPOUND then resolve({ error = 'notparked' }); return end
        fee = math.max(0, math.floor(tonumber(g.fee) or 0))
    else
        if row.state ~= S.GARAGED or row.garage ~= g.id then resolve({ error = 'notparked' }); return end
        fee = math.max(0, math.floor(tonumber(Core.GetSetting('v-garages', 'retrieveFee', 0)) or 0))
    end
    if fee > 0 and not p.RemoveMoney('bank', fee, 'garage-release') then
        resolve({ error = 'funds' }); return
    end

    local netid, err = exports['v-vehicles']:SpawnOwned(source, plate,
        vector3(g.sx + 0.0, g.sy + 0.0, g.sz + 0.0), g.sh)
    if not netid then
        -- the charge must never survive a failed spawn, whichever garage took it
        if fee > 0 then p.AddMoney('bank', fee, 'garage-refund') end
        resolve({ error = err or 'spawn' }); return
    end

    Core.Log('vehicles', ('%s took %s out of %s'):format(p.citizenid, plate, g.id), nil, p.citizenid)
    resolve({ ok = true, netid = netid })
end)

-- ── Store ──────────────────────────────────────────────────────
Core.RegisterCallback('v-garages:store', function(source, resolve, data)
    if type(data) ~= 'table' then resolve(false); return end
    local g = garageById(tostring(data.garage or ''))
    local ok, why = canUse(source, g)
    if not ok then resolve({ error = why }); return end
    if g.type == 'impound' then resolve({ error = 'noimpound' }); return end

    local p = Core.GetPlayer(source)
    local plate = tostring(data.plate or '')
    if not p or plate == '' then resolve(false); return end

    local row = exports['v-vehicles']:GetVehicle(plate)
    if not row or row.citizenid ~= p.citizenid then resolve({ error = 'notyours' }); return end
    if row.state ~= S.OUT then resolve({ error = 'notout' }); return end

    -- The vehicle itself must be at the garage, not just the player: re-read the entity
    -- from the net id the client sent and measure it server-side.
    local ent = data.netid and NetworkGetEntityFromNetworkId(tonumber(data.netid) or 0) or 0
    if not ent or ent == 0 or not DoesEntityExist(ent) then resolve({ error = 'novehicle' }); return end
    if GetVehicleNumberPlateText(ent):gsub('%s+$', '') ~= plate then resolve({ error = 'novehicle' }); return end
    if #(GetEntityCoords(ent) - vector3(g.x + 0.0, g.y + 0.0, g.z + 0.0)) > (Config.Distance + 6.0) then
        resolve({ error = 'far' }); return
    end

    -- Config.StoreMaxDamage: a burning or destroyed wreck cannot be parked, otherwise
    -- the garage is a free repair shop — store it broken, take it out pristine.
    if Core.GetSetting('v-garages', 'storeMaxDamage', Config.StoreMaxDamage) then
        -- Server-side FiveM exposes engine/body/tank health but NOT IsEntityOnFire,
        -- so "on fire" is inferred from the tank, which is what actually burns.
        if GetVehicleEngineHealth(ent) <= 0.0 or GetVehicleBodyHealth(ent) <= 0.0
           or GetVehiclePetrolTankHealth(ent) <= 0.0 then
            resolve({ error = 'wrecked' }); return
        end
    end

    local storeFee = math.floor(tonumber(Core.GetSetting('v-garages', 'storeFee', 0)) or 0)
    if storeFee > 0 and not p.RemoveMoney('bank', storeFee, 'garage-store') then
        resolve({ error = 'fee' }); return
    end

    exports['v-vehicles']:SetGarage(plate, g.id)
    exports['v-vehicles']:DespawnOwned(plate, data.state, S.GARAGED)
    Core.Log('vehicles', ('%s stored %s in %s'):format(p.citizenid, plate, g.id), nil, p.citizenid)
    resolve({ ok = true })
end)

-- ── Boot: seed the config into v-world, then follow the DB ─────
CreateThread(function()
    while GetResourceState('oxmysql') ~= 'started' do Wait(100) end
    local tries = 0
    while GetResourceState('v-world') == 'started' and not exports['v-world']:IsReady() and tries < 100 do
        Wait(100); tries = tries + 1
    end
    if GetResourceState('v-world') == 'started' and exports['v-world']:IsReady() then
        exports['v-world']:SeedGarages(Config.Garages)
    end
    rebuildGarages()
end)

AddEventHandler('v-world:server:changed', function(domain)
    if domain == nil or domain == 'garages' then rebuildGarages() end
end)

RegisterNetEvent('v-garages:server:request', function()
    TriggerClientEvent('v-garages:client:garages', source, Garages)
end)

exports('GetGarages', function() return Garages end)

-- ── Admin-tunable settings ─────────────────────────────────────
local function declareSettings()
    Core.RegisterModule('v-garages', {
        label = 'Garages', category = 'vehicles',
        settings = {
            { key = 'distance', label = 'Interaction range (m)', type = 'number', default = Config.Distance, min = 1, max = 15 },
            { key = 'retrieveFee', label = 'Retrieval fee, public garages ($)', type = 'number', default = 0, min = 0, max = 100000, step = 10 },
            { key = 'storeFee',    label = 'Parking fee ($)', type = 'number', default = 0, min = 0, max = 100000, step = 10 },
            { key = 'storeMaxDamage', label = 'Refuse to park a wreck', type = 'bool', default = Config.StoreMaxDamage },
            { key = 'blips',       label = 'Show garage blips', type = 'bool', default = true },
        },
    })
end

local function applySettings()
    Config.Distance = Core.GetSetting('v-garages', 'distance', Config.Distance)
end

AddEventHandler('v-core:server:settingChanged', function(mod)
    if mod == 'v-garages' then applySettings() end
end)

-- Own boot thread: `local function` is only visible after its definition, so this block
-- declares itself rather than being called from a thread higher up the file.
V.Ready(function()
    declareSettings()
    applySettings()
end)
