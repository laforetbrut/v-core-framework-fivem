
-- v-vehicles | server
-- Owns `character_vehicles`. Everything about an owned car that must be true — who owns
-- it, what its plate is, what condition it is in — is decided here and nowhere else.
--
-- Spawning goes through SpawnOwned(): the server creates the entity (OneSync), so a
-- client cannot conjure an owned vehicle by asking nicely. The client's only job is to
-- read/write the visual mod state of an entity it is already near.
--
-- A car left in the street (state PARKED) is still one of ours: a parking module (v-park)
-- marks it with MarkParked(), brings it back with SpawnOwned(nil, plate) and takes it out of
-- the world with DespawnOwned(). Its row keeps where it stands, and neither the cleanup tick
-- nor a resource stop touches it. See ARCHITECTURE.md, "One spawn path for parked cars".
local Core = exports['v-core']:GetCore()

-- Consumers ask for the capability, not the resource: a server that replaces this
-- module keeps every consumer working.
V.Provide('vehicles')

local Live = {}      -- plate -> { netid, owner, model, since, parked }
local Keys = {}      -- plate -> { [citizenid] = true }  (session-scoped, see Config.Keys.persist)

local S = Config.State

--- GTA pads a plate to eight characters; a row never carries the padding.
local function cleanPlate(plate)
    return (tostring(plate or ''):gsub('^%s+', ''):gsub('%s+$', ''))
end

--- x, y, z out of a vector3, a vector4 or a plain { x, y, z } table, or nil when any of them
--- is missing or not a finite number on the map.
local function toXYZ(c)
    local t = type(c)
    if t ~= 'table' and t ~= 'vector3' and t ~= 'vector4' then return nil end
    local x, y, z = tonumber(c.x or c[1]), tonumber(c.y or c[2]), tonumber(c.z or c[3])
    if not x or not y or not z then return nil end
    for _, v in ipairs({ x, y, z }) do
        if v ~= v or v > 20000.0 or v < -20000.0 then return nil end
    end
    return x + 0.0, y + 0.0, z + 0.0
end

-- ── Schema ─────────────────────────────────────────────────────
-- Where a parked car stands lives on its own row, so the garage, the phone and the parking
-- module all read one record. Added at boot for a database imported before these columns
-- existed; database/schema.sql carries them for a new one. Nothing outside the parked path
-- writes them, so a database that refused the ALTER still runs every other vehicle.
local PARK_COLUMNS = {
    { 'park_x',       'ADD COLUMN `park_x` DOUBLE DEFAULT NULL' },
    { 'park_y',       'ADD COLUMN `park_y` DOUBLE DEFAULT NULL' },
    { 'park_z',       'ADD COLUMN `park_z` DOUBLE DEFAULT NULL' },
    { 'park_heading', 'ADD COLUMN `park_heading` DOUBLE DEFAULT NULL' },
    { 'vehicle_type', 'ADD COLUMN `vehicle_type` VARCHAR(16) DEFAULT NULL' },
    { 'parked_at',    'ADD COLUMN `parked_at` TIMESTAMP NULL DEFAULT NULL' },
}
local schemaReady = false

local function ensureSchema()
    for _, col in ipairs(PARK_COLUMNS) do
        local has = MySQL.scalar.await(
            'SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ? AND COLUMN_NAME = ?',
            { 'character_vehicles', col[1] })
        if not has then MySQL.query.await('ALTER TABLE `character_vehicles` ' .. col[2]) end
    end
    schemaReady = true
end

--- The parking exports can be called by a resource that booted first. Wait for the columns
--- rather than fail on a missing one; false after ten seconds means the migration never ran.
local function waitSchema()
    local tries = 0
    while not schemaReady and tries < 200 do Wait(50); tries = tries + 1 end
    return schemaReady
end

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
local function ownerOf(plate)
    if not plate or plate == '' then return nil end
    return MySQL.scalar.await('SELECT citizenid FROM character_vehicles WHERE plate = ?', { plate })
end

local function ownsPlate(citizenid, plate)
    if not citizenid or not plate then return false end
    return ownerOf(plate) == citizenid
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

-- ── Locks ─────────────────────────────────────────────────────
-- The lock lives here, not on whichever client happens to own the entity. Clients are told
-- the whole set and apply it to vehicles near them. Declared before the exports that read
-- it: a local declared further down is invisible to them, and they would index a nil global.
local Locked = {}      -- [plate] = true

local function pushLocks(src)
    TriggerClientEvent('v-vehicles:client:locks', src or -1, Locked)
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
--- `src` is the player the car comes out for, and their ownership or keys are checked.
--- A server resource putting a PARKED car back in the street (a restore at boot, a parking
--- module streaming it in) passes nil: no player is asking, so none is checked, and the only
--- rows it may bring back are the ones already standing in the street. With no coords such a
--- car comes back where its row says it stands.
---
--- `opts` (optional, server callers only): `rotation` (vector3, full pitch/roll/yaw, for a
--- car parked on a slope), `bucket` (routing bucket), `orphanMode` (defaults to 2, keep, for a
--- spawn without a player: nobody may be near it yet), `cullingRadius`, `vehicleType` (the
--- CreateVehicleServerSetter type; the row's `vehicle_type`, else 'automobile').
---
--- This stays the only function in the framework that creates an owned vehicle's entity.
--- @return netid|nil, errorstring|nil
local function spawnOwned(src, plate, coords, heading, opts)
    opts = type(opts) == 'table' and opts or {}
    local restore = (src == nil or src == 0)
    local p
    if not restore then
        p = Core.GetPlayer(src)
        if not p then return nil, 'noplayer' end
    end
    local row = rowByPlate(plate)
    if not row then return nil, 'unknown' end
    local parked = row.state == S.PARKED
    if restore then
        if not parked then return nil, 'notparked' end
    elseif row.citizenid ~= p.citizenid and not hasKeys(src, plate) then
        return nil, 'notyours'
    end
    if Live[plate] then return nil, 'already' end

    if coords == nil and parked and row.park_x then
        coords = { x = row.park_x, y = row.park_y, z = row.park_z }
        if heading == nil then heading = row.park_heading end
    end
    local x, y, z = toXYZ(coords)
    if not x then return nil, 'coords' end
    local h = (tonumber(heading) or 0.0) + 0.0

    local model = row.model
    local veh
    if restore and CreateVehicleServerSetter then
        -- No player may be connected yet. The RPC CreateVehicle needs a client to answer
        -- before the entity is real; the setter registers it with the server at once.
        local kind = tostring(opts.vehicleType or row.vehicle_type or 'automobile')
        local hash = type(model) == 'number' and model or GetHashKey(model)
        local ok, ent = pcall(CreateVehicleServerSetter, hash, kind, x, y, z, h)
        if ok and ent and ent ~= 0 then veh = ent end
    end
    if not veh then
        veh = CreateVehicle(model, x, y, z, h, true, true)
    end
    if not veh or veh == 0 then return nil, 'spawn' end

    -- wait for the entity to actually exist before touching it
    local tries = 0
    while not DoesEntityExist(veh) and tries < 100 do Wait(10); tries = tries + 1 end
    if not DoesEntityExist(veh) then return nil, 'spawn' end

    SetVehicleNumberPlateText(veh, plate)
    local rx, ry, rz = toXYZ(opts.rotation)
    if rx then SetEntityRotation(veh, rx, ry, rz, 2, true) end
    if tonumber(opts.bucket) then SetEntityRoutingBucket(veh, math.floor(tonumber(opts.bucket))) end
    local orphan = opts.orphanMode
    if orphan == nil and restore then orphan = 2 end
    if tonumber(orphan) and SetEntityOrphanMode then pcall(SetEntityOrphanMode, veh, math.floor(tonumber(orphan))) end
    if tonumber(opts.cullingRadius) and SetEntityDistanceCullingRadius then
        pcall(SetEntityDistanceCullingRadius, veh, tonumber(opts.cullingRadius) + 0.0)
    end

    local netid = NetworkGetNetworkIdFromEntity(veh)
    Live[plate] = { netid = netid, owner = row.citizenid, model = model, since = os.time(), parked = parked or nil }
    -- A parked car stays parked when it comes back: it is in the street, nobody is driving it.
    if not parked then
        MySQL.update.await('UPDATE character_vehicles SET state = ? WHERE plate = ?', { S.OUT, plate })
    end

    -- hand the stored condition to the client so it can dress the entity. A restore has no
    -- client to ask: the caller dresses it when a player gets it in scope (v-park does).
    if not restore then
        TriggerClientEvent('v-vehicles:client:applyState', src, netid, {
            props = row.props, fuel = row.fuel, engine = row.engine, body = row.body, plate = plate,
        })
    end
    -- let the modules that own their own slice of a vehicle (wear, fuel, …) hydrate it.
    -- `src` is nil for a restore.
    TriggerEvent('v-vehicles:server:spawned', src, plate, netid, row)
    return netid, nil
end

--- Leave the street: the row forgets where the car stood. The only writer of the park
--- columns besides MarkParked.
local function clearPark(plate, newState)
    MySQL.update.await([[UPDATE character_vehicles SET state = ?, park_x = NULL, park_y = NULL,
        park_z = NULL, park_heading = NULL, parked_at = NULL WHERE plate = ?]], { newState, plate })
    if Live[plate] then Live[plate].parked = nil end
    TriggerEvent('v-vehicles:server:unparked', plate, newState)
end

--- Delete a live owned vehicle and write its condition back. `data` is optional and comes
--- from the caller's client when it has just read the entity. Without `newState` the state
--- is kept: a parked car taken out of the world (a parking module streaming it out) is still
--- parked, and comes back with SpawnOwned(nil, plate).
local function despawnOwned(plate, data, newState)
    local live = Live[plate]
    if not live then return false end
    if newState == S.PARKED and not live.parked then return false, 'notparked' end
    persist(plate, data)
    local ent = NetworkGetEntityFromNetworkId(live.netid)
    if ent and ent ~= 0 and DoesEntityExist(ent) then DeleteEntity(ent) end
    Live[plate] = nil
    if newState and newState ~= S.PARKED then
        if live.parked then
            clearPark(plate, newState)
        else
            MySQL.update.await('UPDATE character_vehicles SET state = ? WHERE plate = ?', { newState, plate })
        end
    end
    return true
end

-- ── Parked in the street ───────────────────────────────────────
--- The server entity of a live plate, or nil when it is not in the world.
--- @return entity|nil, netid|nil
local function liveEntity(plate)
    local live = Live[plate]
    if not live then return nil end
    local ent = NetworkGetEntityFromNetworkId(live.netid)
    if not ent or ent == 0 or not DoesEntityExist(ent) then return nil end
    return ent, live.netid
end

--- Mark a car as parked in the street where it stands. `coords`/`heading` default to the
--- live entity's own; `data` is the optional condition ({ props, fuel, engine, body }, same
--- clamping as a client report) plus `vehicleType` for the server-side respawn. Only a car
--- that is out (or already parked, to move it) can be parked: one in a garage or the impound
--- is not in the street.
--- @return true|false, errorstring|nil
local function markParked(plate, coords, heading, data)
    plate = cleanPlate(plate)
    if plate == '' then return false, 'unknown' end
    if not waitSchema() then return false, 'schema' end
    local row = rowByPlate(plate)
    if not row then return false, 'unknown' end
    if row.state ~= S.OUT and row.state ~= S.PARKED then return false, 'stored' end

    local ent = liveEntity(plate)
    if coords == nil and ent then
        coords = GetEntityCoords(ent)
        if heading == nil then heading = GetEntityHeading(ent) end
    end
    local x, y, z = toXYZ(coords)
    if not x then return false, 'coords' end
    local h = (tonumber(heading) or 0.0) % 360.0

    data = type(data) == 'table' and data or nil
    local kind = data and data.vehicleType
    if not kind and ent and GetVehicleType then
        local ok, t = pcall(GetVehicleType, ent)
        if ok and type(t) == 'string' and t ~= '' then kind = t end
    end
    kind = kind and tostring(kind):sub(1, 16) or nil

    if data then persist(plate, data) end
    MySQL.update.await([[UPDATE character_vehicles SET state = ?, park_x = ?, park_y = ?, park_z = ?,
        park_heading = ?, vehicle_type = COALESCE(?, vehicle_type), parked_at = CURRENT_TIMESTAMP
        WHERE plate = ?]], { S.PARKED, x, y, z, h, kind, plate })
    if Live[plate] then Live[plate].parked = true end
    TriggerEvent('v-vehicles:server:parked', plate, vector3(x, y, z), h)
    return true
end

--- A parked car somebody is driving away again: back to OUT, position forgotten. The car
--- has to be in the world; a parked car that is not goes somewhere with SetState instead.
local function unpark(plate)
    plate = cleanPlate(plate)
    local live = Live[plate]
    if not live then return false, 'notlive' end
    if not live.parked then return false, 'notparked' end
    clearPark(plate, S.OUT)
    return true
end

--- Every car standing in the street, optionally one owner's, with `coords`, `heading`,
--- `parkedAt` (unix seconds) and `live` filled in.
local function parkedRows(citizenid)
    if not waitSchema() then return {} end
    local rows
    if citizenid then
        rows = MySQL.query.await([[SELECT *, UNIX_TIMESTAMP(parked_at) AS parked_ts FROM character_vehicles
            WHERE state = ? AND citizenid = ? ORDER BY id]], { S.PARKED, tostring(citizenid) })
    else
        rows = MySQL.query.await([[SELECT *, UNIX_TIMESTAMP(parked_at) AS parked_ts FROM character_vehicles
            WHERE state = ? ORDER BY id]], { S.PARKED })
    end
    local out = {}
    for _, r in ipairs(rows or {}) do
        r = decodeRow(r)
        if r.park_x then
            r.coords = vector3(r.park_x + 0.0, r.park_y + 0.0, r.park_z + 0.0)
            r.heading = (tonumber(r.park_heading) or 0.0) + 0.0
        end
        r.parkedAt = tonumber(r.parked_ts)
        r.parked_ts = nil
        r.live = Live[r.plate] ~= nil
        out[#out + 1] = r
    end
    return out
end

--- A restart of this resource alone leaves the parked cars standing (onResourceStop spares
--- them) but forgets their handles. Find them again before anybody spawns a second copy.
local function adoptParked()
    local rows = MySQL.query.await('SELECT plate, citizenid, model FROM character_vehicles WHERE state = ?',
        { S.PARKED }) or {}
    if #rows == 0 then return 0 end
    local want = {}
    for _, r in ipairs(rows) do want[r.plate] = r end
    local n = 0
    for _, ent in ipairs(GetAllVehicles() or {}) do
        local plate = cleanPlate(GetVehicleNumberPlateText(ent))
        local r = want[plate]
        -- same model too: a plate text alone is what a fake plate would copy
        if r and not Live[plate]
           and (GetEntityModel(ent) & 0xFFFFFFFF) == (GetHashKey(r.model) & 0xFFFFFFFF) then
            Live[plate] = { netid = NetworkGetNetworkIdFromEntity(ent), owner = r.citizenid,
                            model = r.model, since = os.time(), parked = true }
            n = n + 1
        end
    end
    return n
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
exports('SpawnOwned',    function(src, plate, coords, heading, opts) return spawnOwned(src, plate, coords, heading, opts) end)
exports('DespawnOwned',  function(plate, data, state) return despawnOwned(plate, data, state) end)
exports('CreateOwned',   function(cid, model, garage, props) return createOwned(cid, model, garage, props) end)
exports('IsLive',        function(plate) return Live[plate] ~= nil end)
exports('IsLocked',      function(plate) return Locked[tostring(plate or '')] == true end)
exports('SetLocked',     function(plate, on)
    plate = tostring(plate or ''):gsub('%s+$', '')
    if plate == '' then return false end
    Locked[plate] = on and true or nil
    pushLocks()
    return true
end)
exports('SetState',      function(plate, state)
    -- A parked car needs a position, which only MarkParked takes.
    if tonumber(state) == S.PARKED then return false, 'usemarkparked' end
    local live = Live[plate]
    local wasParked = (live and live.parked) or (not live and (rowByPlate(plate) or {}).state == S.PARKED)
    if wasParked then
        clearPark(plate, state)
    else
        MySQL.update.await('UPDATE character_vehicles SET state = ? WHERE plate = ?', { state, plate })
    end
    return true
end)
-- The parking surface (v-park): see ARCHITECTURE.md, "One spawn path for parked cars".
exports('MarkParked',    function(plate, coords, heading, data) return markParked(plate, coords, heading, data) end)
exports('Unpark',        function(plate) return unpark(plate) end)
exports('GetParked',     function(citizenid) return parkedRows(citizenid) end)
exports('GetPlateOwner', function(plate) return ownerOf(cleanPlate(plate)) end)
exports('GetEntity',     function(plate) return liveEntity(cleanPlate(plate)) end)
exports('SetGarage',     function(plate, garage)
    MySQL.update.await('UPDATE character_vehicles SET garage = ? WHERE plate = ?', { garage, plate })
    return true
end)

-- ── Client-driven checks ───────────────────────────────────────
-- The client asks before starting an engine or toggling a lock. The answer is derived
-- server-side; the client-side gate that follows is UX, not security.
RegisterNetEvent('v-vehicles:server:requestLocks', function() pushLocks(source) end)

Core.RegisterCallback('v-vehicles:toggleLock', function(source, resolve, data)
    local plate = tostring((data and data.plate) or ''):gsub('%s+$', '')
    if plate == '' then resolve({ error = 'novehicle' }) return end
    if not hasKeys(source, plate) then resolve({ error = 'nokeys' }) return end

    -- Proximity is re-derived: a key that works from across the map is not a key.
    local ped = GetPlayerPed(source)
    if not ped or ped == 0 then resolve(false) return end
    local range = tonumber(Config.Controls and Config.Controls.lockRange) or 6.0
    local veh = 0
    for _, ent in ipairs(GetAllVehicles and GetAllVehicles() or {}) do
        if GetVehicleNumberPlateText(ent):gsub('%s+$', '') == plate then veh = ent break end
    end
    if veh ~= 0 and #(GetEntityCoords(ped) - GetEntityCoords(veh)) > (range + 3.0) then
        resolve({ error = 'far' }) return
    end

    Locked[plate] = not Locked[plate] or nil
    pushLocks()
    resolve({ ok = true, locked = Locked[plate] == true })
end)

--- The engine gate. With `lockEngine` on, no keys means no engine - and that is not a
--- decision a client gets to make about a car it does not own.
Core.RegisterCallback('v-vehicles:engine', function(source, resolve, data)
    local plate = tostring((data and data.plate) or ''):gsub('%s+$', '')
    if plate == '' then resolve(false) return end
    if not Config.Keys.lockEngine then resolve(true) return end
    resolve(hasKeys(source, plate) == true)
end)

-- ── Lockpicking ───────────────────────────────────────────────
-- The illegal counterpart of a key. A failure is what draws attention: a clean job should
-- be quiet, or there is no reason to be good at it.
Core.RegisterCallback('v-vehicles:lockpick', function(source, resolve, data)
    local p = Core.GetPlayer(source)
    local plate = tostring((data and data.plate) or ''):gsub('%s+$', '')
    if not p or plate == '' then resolve(false) return end
    if not Core.GetSetting('v-vehicles', 'lockpicking', true) then resolve({ error = 'off' }) return end
    if not Locked[plate] then resolve({ error = 'notlocked' }) return end
    if hasKeys(source, plate) then resolve({ error = 'haskeys' }) return end

    local item = tostring(Core.GetSetting('v-vehicles', 'lockpickItem', Config.Lockpick.item) or '')
    if item ~= '' then
        local n = exports['v-inventory'] and exports['v-inventory']:GetItemCount(source, item) or 0
        if (tonumber(n) or 0) < 1 then resolve({ error = 'nopick' }) return end
    end

    -- The wait happens here, so a client that skips its own animation gains nothing.
    local seconds = math.max(1, math.floor(tonumber(Core.GetSetting('v-vehicles', 'lockpickSeconds', Config.Lockpick.seconds)) or 8))
    Wait(seconds * 1000)

    -- Still there? A player who walked away mid-pick does not get the car.
    local ped = GetPlayerPed(source)
    if not ped or ped == 0 then resolve(false) return end

    local chance = tonumber(Core.GetSetting('v-vehicles', 'lockpickChance', Config.Lockpick.chance)) or 0.45
    local ok = math.random() < math.max(0.0, math.min(1.0, chance))

    local broke = false
    if not ok then
        local br = tonumber(Core.GetSetting('v-vehicles', 'lockpickBreak', Config.Lockpick.breakChance)) or 0.3
        broke = math.random() < br
        if broke and item ~= '' then
            pcall(function() exports['v-inventory']:RemoveItem(source, item, 1) end)
        end
    end

    if ok then
        Locked[plate] = nil
        pushLocks()
        giveKeys(source, plate)
        Core.Log('vehicles', ('%s lockpicked %s'):format(p.citizenid, plate), nil, p.citizenid)
    end

    -- Noticed, not caught: the alert is a lead for the police, not an arrest.
    if Core.GetSetting('v-vehicles', 'lockpickAlert', Config.Lockpick.alertPolice) then
        local alertChance = tonumber(Core.GetSetting('v-vehicles', 'lockpickAlertChance', Config.Lockpick.alertChance)) or 0.5
        if (not ok) or math.random() < alertChance then
            local coords = GetEntityCoords(ped)
            for _, sid in ipairs(GetPlayers()) do
                local o = tonumber(sid)
                if o and GetResourceState('v-police') == 'started' then
                    local isCop = false
                    pcall(function() isCop = exports['v-police']:IsCop(o) == true end)
                    if isCop then
                        TriggerClientEvent('v-drugs:client:bustAlert', o, coords, 70.0)
                    end
                end
            end
        end
    end

    resolve({ ok = ok, broke = broke })
end)

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
-- garbage-collected by the engine) so the plate can be taken out again. A car that was out
-- goes to the impound; a parked one only leaves the index: its row still says where it
-- stands, and the parking module puts it back from there.
CreateThread(function()
    while true do
        Wait(30000)
        -- collected first: the awaits below yield, and a spawn in between would add a key
        -- to the table this loop is walking
        local gone = {}
        for plate, live in pairs(Live) do
            local ent = NetworkGetEntityFromNetworkId(live.netid)
            if not ent or ent == 0 or not DoesEntityExist(ent) then gone[#gone + 1] = plate end
        end
        for _, plate in ipairs(gone) do
            local live = Live[plate]
            Live[plate] = nil
            if live and not live.parked then
                MySQL.update.await('UPDATE character_vehicles SET state = ? WHERE plate = ?', { S.IMPOUND, plate })
            end
        end
    end
end)

-- Cars that are out go back to their garage. Parked ones stay exactly where they are, entity
-- and row: that is what lets a car left in the street survive a restart.
AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for plate, live in pairs(Live) do
        if not live.parked then
            local ent = NetworkGetEntityFromNetworkId(live.netid)
            if ent and ent ~= 0 and DoesEntityExist(ent) then DeleteEntity(ent) end
            MySQL.update.await('UPDATE character_vehicles SET state = ? WHERE plate = ?', { S.GARAGED, plate })
        end
    end
end)

-- Boot: the park columns, then the parked cars a restart of this resource alone left standing.
CreateThread(function()
    while GetResourceState('oxmysql') ~= 'started' do Wait(100) end
    local ok, err = pcall(ensureSchema)
    if not ok then
        print(('[v-vehicles] could not add the parking columns to character_vehicles: %s'):format(tostring(err)))
        return
    end
    local n = adoptParked()
    if n > 0 then print(('[v-vehicles] found %d parked vehicle(s) still in the world'):format(n)) end
end)

-- ── Admin-tunable settings ─────────────────────────────────────
local function declareSettings()
    Core.RegisterModule('v-vehicles', {
        label = 'Vehicles & keys', category = 'vehicles',
        settings = {
            { key = 'saveInterval', label = 'Condition save interval (s)', type = 'number', default = Config.SaveInterval, min = 15, max = 900, step = 1 },
            { key = 'lockEngine',   label = 'No keys, no engine',         type = 'bool',   default = Config.Keys.lockEngine },
            { key = 'platePrefix',  label = 'Plate prefix',               type = 'string', default = Config.PlatePrefix, maxLength = 3 },
            { key = 'leaveRunning', label = 'Engine keeps running when the driver gets out', type = 'bool', default = true },
            { key = 'lockpicking',  label = 'Lockpicking enabled',        type = 'bool',   default = true },
            { key = 'lockpickItem', label = 'Lockpick item (blank = none)', type = 'string', default = Config.Lockpick.item, maxLength = 40 },
            { key = 'lockpickSeconds', label = 'Lockpick attempt (s)',    type = 'number', default = Config.Lockpick.seconds, min = 1, max = 120, step = 1 },
            { key = 'lockpickChance', label = 'Lockpick success chance',  type = 'number', default = Config.Lockpick.chance, min = 0, max = 1, step = 0.05 },
            { key = 'lockpickBreak', label = 'Chance the pick snaps on a failure', type = 'number', default = Config.Lockpick.breakChance, min = 0, max = 1, step = 0.05 },
            { key = 'lockpickAlert', label = 'Lockpicking can alert the police', type = 'bool', default = Config.Lockpick.alertPolice },
            { key = 'lockpickAlertChance', label = 'Chance a successful pick is noticed', type = 'number', default = Config.Lockpick.alertChance, min = 0, max = 1, step = 0.05 },
            { key = 'seatbelt',     label = 'Seatbelt enabled',           type = 'bool',   default = true },
            { key = 'ejectDrop',    label = 'Eject on speed drop over (km/h)', type = 'number', default = 55, min = 20, max = 200, step = 1 },
            { key = 'ejectMinSpeed', label = 'No ejection below (km/h)',  type = 'number', default = 60, min = 10, max = 200, step = 1 },
            { key = 'ejectDamage',  label = 'Ejection damage (HP)',       type = 'number', default = 22, min = 0, max = 100, step = 1 },
        },
    })
end

local function applySettings()
    Config.SaveInterval    = Core.GetSetting('v-vehicles', 'saveInterval', Config.SaveInterval)
    Config.Keys.lockEngine = Core.GetSetting('v-vehicles', 'lockEngine', Config.Keys.lockEngine)
    Config.PlatePrefix     = Core.GetSetting('v-vehicles', 'platePrefix', Config.PlatePrefix)
end

AddEventHandler('v-core:server:settingChanged', function(mod)
    if mod == 'v-vehicles' then applySettings() end
end)

CreateThread(function()
    Wait(2500)
    declareSettings()
    applySettings()
end)
