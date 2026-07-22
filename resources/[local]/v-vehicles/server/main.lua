-- v-vehicles | server
-- Owns `character_vehicles`. Everything about an owned car that must be true — who owns
-- it, what its plate is, what condition it is in — is decided here and nowhere else.
--
-- Spawning goes through SpawnOwned(): the server creates the entity (OneSync), so a
-- client cannot conjure an owned vehicle by asking nicely. The client's only job is to
-- read/write the visual mod state of an entity it is already near.
local Core = exports['v-core']:GetCore()

local Live = {}      -- plate -> { netid, owner, model, since }
local Keys = {}      -- plate -> { [citizenid] = true }  (session-scoped, see Config.Keys.persist)

local S = Config.State

-- ── Plates ─────────────────────────────────────────────────────
local function randomPlate()
    local n = ''
    for _ = 1, Config.PlateDigits do n = n .. tostring(math.random(0, 9)) end
    return (Config.PlatePrefix .. n):sub(1, 8)
end

--- Mint a plate that is free in the DB. Returns nil after 25 collisions, which would
--- mean the plate space is exhausted — better to fail loudly than to hand out a dupe.
local function mintPlate()
    for _ = 1, 25 do
        local p = randomPlate()
        if not MySQL.scalar.await('SELECT 1 FROM character_vehicles WHERE plate = ?', { p }) then
            return p
        end
    end
    print('[v-vehicles] could not mint a free plate after 25 tries')
    return nil
end

-- ── Row helpers ────────────────────────────────────────────────
local function decodeRow(r)
    if not r then return nil end
    local props = r.props
    if type(props) == 'string' then props = json.decode(props) or {} end
    r.props = props or {}
    return r
end

local function rowByPlate(plate)
    return decodeRow(MySQL.single.await('SELECT * FROM character_vehicles WHERE plate = ?', { plate }))
end

local function ownedBy(citizenid)
    local out = {}
    for _, r in ipairs(MySQL.query.await(
        'SELECT * FROM character_vehicles WHERE citizenid = ? ORDER BY id', { citizenid }) or {}) do
        out[#out + 1] = decodeRow(r)
    end
    return out
end

-- ── Keys ───────────────────────────────────────────────────────
local function ownsPlate(citizenid, plate)
    if not citizenid or not plate then return false end
    local owner = MySQL.scalar.await('SELECT citizenid FROM character_vehicles WHERE plate = ?', { plate })
    return owner == citizenid
end

--- The owner always has keys; anyone else only if they were handed a set this session.
local function hasKeys(src, plate)
    local p = Core.GetPlayer(src)
    if not p or not plate then return false end
    if Keys[plate] and Keys[plate][p.citizenid] then return true end
    return ownsPlate(p.citizenid, plate)
end

local function giveKeys(src, plate)
    local p = Core.GetPlayer(src)
    if not p or not plate then return false end
    Keys[plate] = Keys[plate] or {}
    Keys[plate][p.citizenid] = true
    TriggerClientEvent('v-vehicles:client:keys', src, plate, true)
    return true
end

local function removeKeys(src, plate)
    local p = Core.GetPlayer(src)
    if not p or not plate or not Keys[plate] then return false end
    Keys[plate][p.citizenid] = nil
    TriggerClientEvent('v-vehicles:client:keys', src, plate, false)
    return true
end

-- ── Persistence ────────────────────────────────────────────────
--- Write a vehicle's condition back to its row. `data` comes from the client that owns
--- the entity, so every field is coerced and clamped: a patched client may lie about its
--- own fuel, but it cannot corrupt the row or reach into another plate.
local function persist(plate, data)
    local row = rowByPlate(plate)
    if not row then return false end
    data = type(data) == 'table' and data or {}

    local fuel   = math.floor(tonumber(data.fuel) or row.fuel or 100)
    local engine = math.floor(tonumber(data.engine) or row.engine or 1000)
    local body   = math.floor(tonumber(data.body) or row.body or 1000)
    fuel   = math.max(0, math.min(100, fuel))
    engine = math.max(0, math.min(1000, engine))
    body   = math.max(0, math.min(1000, body))

    local props = (type(data.props) == 'table') and data.props or row.props
    MySQL.update.await('UPDATE character_vehicles SET props = ?, fuel = ?, engine = ?, body = ? WHERE plate = ?',
        { json.encode(props or {}), fuel, engine, body, plate })
    return true
end

--- Ask the client that is closest to the vehicle for its current condition, then store it.
--- Used by the save tick; store/despawn paths send the data with the request instead.
local function requestPersist(plate)
    local live = Live[plate]
    if not live then return end
    TriggerClientEvent('v-vehicles:client:reportState', -1, plate, live.netid)
end

RegisterNetEvent('v-vehicles:server:reportState', function(plate, data)
    local src = source
    if type(plate) ~= 'string' or not Live[plate] then return end
    -- only a player who can legitimately drive it may report its condition
    if not hasKeys(src, plate) then return end
    persist(plate, data)
end)

-- ── Spawning (the single legitimate path for an owned vehicle) ──
--- @return netid|nil, errorstring|nil
local function spawnOwned(src, plate, coords, heading)
    local p = Core.GetPlayer(src)
    if not p then return nil, 'noplayer' end
    local row = rowByPlate(plate)
    if not row then return nil, 'unknown' end
    if row.citizenid ~= p.citizenid and not hasKeys(src, plate) then return nil, 'notyours' end
    if Live[plate] then return nil, 'already' end

    local model = row.model
    local veh = CreateVehicle(model, coords.x + 0.0, coords.y + 0.0, coords.z + 0.0, (heading or 0.0) + 0.0, true, true)
    if not veh or veh == 0 then return nil, 'spawn' end

    -- wait for the entity to actually exist before touching it
    local tries = 0
    while not DoesEntityExist(veh) and tries < 100 do Wait(10); tries = tries + 1 end
    if not DoesEntityExist(veh) then return nil, 'spawn' end

    SetVehicleNumberPlateText(veh, plate)
    local netid = NetworkGetNetworkIdFromEntity(veh)
    Live[plate] = { netid = netid, owner = row.citizenid, model = model, since = os.time() }
    MySQL.update.await('UPDATE character_vehicles SET state = ? WHERE plate = ?', { S.OUT, plate })

    -- hand the stored condition to the client so it can dress the entity
    TriggerClientEvent('v-vehicles:client:applyState', src, netid, {
        props = row.props, fuel = row.fuel, engine = row.engine, body = row.body, plate = plate,
    })
    return netid, nil
end

--- Delete a live owned vehicle and write its condition back. `data` is optional and comes
--- from the caller's client when it has just read the entity.
local function despawnOwned(plate, data, newState)
    local live = Live[plate]
    if not live then return false end
    persist(plate, data)
    local ent = NetworkGetEntityFromNetworkId(live.netid)
    if ent and ent ~= 0 and DoesEntityExist(ent) then DeleteEntity(ent) end
    Live[plate] = nil
    if newState then
        MySQL.update.await('UPDATE character_vehicles SET state = ? WHERE plate = ?', { newState, plate })
    end
    return true
end

-- ── Creating an owned vehicle (dealership / admin / job grant) ──
--- @return plate|nil, errorstring|nil
local function createOwned(citizenid, model, garage, props)
    if type(citizenid) ~= 'string' or citizenid == '' then return nil, 'owner' end
    model = tostring(model or ''):lower()
    if model == '' then return nil, 'model' end
    local plate = mintPlate()
    if not plate then return nil, 'plate' end
    MySQL.insert.await([[INSERT INTO character_vehicles (citizenid, plate, model, props, garage, state, fuel, engine, body)
        VALUES (?,?,?,?,?,?,100,1000,1000)]],
        { citizenid, plate, model, json.encode(props or {}), garage or 'legion', S.GARAGED })
    return plate, nil
end

-- ── Exports (the surface other modules use — never touch the table directly) ──
exports('GetOwned',      function(src)
    local p = Core.GetPlayer(src)
    return p and ownedBy(p.citizenid) or {}
end)
exports('GetOwnedByCid', function(cid) return ownedBy(cid) end)
exports('GetVehicle',    function(plate) return rowByPlate(plate) end)
exports('IsOwner',       function(cid, plate) return ownsPlate(cid, plate) end)
exports('HasKeys',       function(src, plate) return hasKeys(src, plate) end)
exports('GiveKeys',      function(src, plate) return giveKeys(src, plate) end)
exports('RemoveKeys',    function(src, plate) return removeKeys(src, plate) end)
exports('SpawnOwned',    function(src, plate, coords, heading) return spawnOwned(src, plate, coords, heading) end)
exports('DespawnOwned',  function(plate, data, state) return despawnOwned(plate, data, state) end)
exports('CreateOwned',   function(cid, model, garage, props) return createOwned(cid, model, garage, props) end)
exports('IsLive',        function(plate) return Live[plate] ~= nil end)
exports('SetState',      function(plate, state)
    MySQL.update.await('UPDATE character_vehicles SET state = ? WHERE plate = ?', { state, plate })
    return true
end)
exports('SetGarage',     function(plate, garage)
    MySQL.update.await('UPDATE character_vehicles SET garage = ? WHERE plate = ?', { garage, plate })
    return true
end)

-- ── Client-driven checks ───────────────────────────────────────
-- The client asks before starting an engine or toggling a lock. The answer is derived
-- server-side; the client-side gate that follows is UX, not security.
Core.RegisterCallback('v-vehicles:hasKeys', function(source, resolve, plate)
    resolve(hasKeys(source, tostring(plate or '')) and true or false)
end)

Core.RegisterCallback('v-vehicles:myVehicles', function(source, resolve)
    local p = Core.GetPlayer(source)
    if not p then resolve(false); return end
    local out = {}
    for _, r in ipairs(ownedBy(p.citizenid)) do
        out[#out + 1] = { plate = r.plate, model = r.model, garage = r.garage, state = r.state,
                          fuel = r.fuel, engine = r.engine, body = r.body, live = Live[r.plate] ~= nil }
    end
    resolve(out)
end)

-- Give another nearby player a set of keys.
Core.RegisterCallback('v-vehicles:shareKeys', function(source, resolve, data)
    local p = Core.GetPlayer(source)
    local plate = type(data) == 'table' and tostring(data.plate or '') or ''
    local target = type(data) == 'table' and tonumber(data.target) or nil
    if not p or plate == '' or not target then resolve(false); return end
    if not ownsPlate(p.citizenid, plate) then resolve({ error = 'notyours' }); return end

    -- proximity is re-derived from the server-owned peds, never taken from the client
    local a, b = GetPlayerPed(source), GetPlayerPed(target)
    if not a or not b or a == 0 or b == 0 then resolve({ error = 'gone' }); return end
    if #(GetEntityCoords(a) - GetEntityCoords(b)) > 5.0 then resolve({ error = 'far' }); return end

    giveKeys(target, plate)
    Core.Notify(target, LP(target, 'veh.keys_got', plate), 'success')
    Core.Log('vehicles', ('%s shared the keys of %s'):format(p.citizenid, plate), { target = target }, p.citizenid)
    resolve({ ok = true })
end)

-- ── Save tick + cleanup ────────────────────────────────────────
CreateThread(function()
    while true do
        Wait((Config.SaveInterval or 120) * 1000)
        for plate in pairs(Live) do requestPersist(plate) end
    end
end)

-- A disconnecting owner's cars are not deleted (a passenger may still be in one), but
-- their condition is written down while we still know it.
AddEventHandler('playerDropped', function()
    local p = Core.GetPlayer(source)
    if not p then return end
    for plate, live in pairs(Live) do
        if live.owner == p.citizenid then requestPersist(plate) end
    end
end)

-- Remove entities that no longer exist from the live index (a vehicle blown up, or
-- garbage-collected by the engine) so the plate can be taken out again.
CreateThread(function()
    while true do
        Wait(30000)
        for plate, live in pairs(Live) do
            local ent = NetworkGetEntityFromNetworkId(live.netid)
            if not ent or ent == 0 or not DoesEntityExist(ent) then
                Live[plate] = nil
                MySQL.update.await('UPDATE character_vehicles SET state = ? WHERE plate = ?', { S.IMPOUND, plate })
            end
        end
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for plate, live in pairs(Live) do
        local ent = NetworkGetEntityFromNetworkId(live.netid)
        if ent and ent ~= 0 and DoesEntityExist(ent) then DeleteEntity(ent) end
        MySQL.update.await('UPDATE character_vehicles SET state = ? WHERE plate = ?', { S.GARAGED, plate })
    end
end)
