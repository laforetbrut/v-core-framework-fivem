-- Author: vyrriox
--[[
    bridge/server/vcore.lua

    The v-core adapter, and the one place v-park meets the framework's vehicle modules.

    -------------------------------------------------------------------------------------------
    WHY IT IS MORE THAN AN ADAPTER
    -------------------------------------------------------------------------------------------

    On qb-core, ESX or ox_core a framework owns the player and a table of owned vehicles, and
    v-park creates the cars itself. On v-core the cars belong to the framework too:

        v-vehicles   `character_vehicles`: who owns a car, its state, where a parked car stands,
                     the keys - and the ONLY function allowed to create an owned car's entity,
                     `SpawnOwned`. Keys, locks, garages, the impound, the dealership, the
                     mechanic and the phone all read that one record.
        v-garages    the garage list, and so where a car goes home to.
        v-fuel       consumption. The level itself lives in v-vehicles (client side).
        v-notify     the toasts (client side, bridge/client/compat.lua).

    So v-park keeps deciding WHEN a parked car is in the world - its streaming radius, its
    placement, its appearance data - and v-vehicles does everything else. v-park's own table
    stays a cache of the appearance (deformation, dirt, windows) keyed by plate, never the
    ownership record. ARCHITECTURE.md of v-core, "One spawn path for parked cars", is the
    decision this file carries out.

    -------------------------------------------------------------------------------------------
    THE MAPPING
    -------------------------------------------------------------------------------------------

        v-park streams a car in       SpawnOwned(nil, plate, coords, heading, opts)
        v-park streams it out         DespawnOwned(plate)                 the row stays PARKED
        a player leaves it, a pose    MarkParked(plate, coords, heading, condition)
        a player gets in to drive     Unpark(plate)                       OUT, v-vehicles' car
        v-park forgets it             in the world: Unpark; otherwise back to its garage
        v-vehicles takes it off the   (v-vehicles:server:unparked, garage or impound): the
        street                        record is forgotten, the garage is the truth

    Only a car `character_vehicles` knows is kept: an ambient car has no row to park, and
    creating one here would be the second spawn path the framework forbids.

    -------------------------------------------------------------------------------------------
    ONE QUEUE
    -------------------------------------------------------------------------------------------

    Every call that writes to v-vehicles runs on one queue, in the order it was asked for, and
    a spawn waits its turn on the same queue. Without it a despawn still waiting for its
    database round trip could run after the next spawn of the same plate and delete the car
    that had just come back. The feature files never wait on it, except the spawn, which must
    hand an entity back.

    Every function below answers nil, or does nothing, when the framework is not v-core, so on
    every other framework v-park behaves exactly as upstream.
]]

local VEHICLES = 'v-vehicles'

-- v-vehicles' Config.State. Copied rather than read: a shared config of another resource is
-- not something this one loads.
local STATE = { OUT = 0, GARAGED = 1, IMPOUND = 2, PARKED = 3 }

local function resourceName(key, fallback)
    local named = Config and Config.Compat and Config.Compat.resources and Config.Compat.resources[key]
    if type(named) == 'string' and named ~= '' then return named end
    return fallback
end

local function active()
    return Bridge.kind() == 'vcore'
end

Bridge.isVCore = active

-- ---------------------------------------------------------------------------------------
-- Calling v-vehicles
-- ---------------------------------------------------------------------------------------

--[[
    `ok, ...` for an export of v-vehicles. `ok` is false when it is not started or raised,
    and the raise is a debug line: the caller decides what a missing answer means.
]]
local function call(method, ...)
    if not Park.started(VEHICLES) then return false end

    local args = table.pack(...)
    local results = table.pack(pcall(function()
        return exports[VEHICLES][method](nil, table.unpack(args, 1, args.n))
    end))

    if not results[1] then
        Park.debug('v-vehicles:%s raised: %s', method, tostring(results[2]))
        return false
    end

    return true, table.unpack(results, 2, results.n)
end

local function row(plate)
    if not plate then return nil end
    local ok, found = call('GetVehicle', plate)
    if ok and type(found) == 'table' then return found end
    return nil
end

local function stateOf(found)
    return found and tonumber(found.state) or nil
end

local function isLive(plate)
    local ok, live = call('IsLive', plate)
    return ok and live == true
end

-- ---------------------------------------------------------------------------------------
-- The queue
-- ---------------------------------------------------------------------------------------

local jobs, head, tail = {}, 1, 0
local working = false

local function work()
    if working then return end
    working = true

    CreateThread(function()
        while head <= tail do
            local job = jobs[head]
            jobs[head] = nil
            head = head + 1

            if not job.cancelled then
                job.started = true
                job.result = table.pack(pcall(job.fn))
                if not job.result[1] then
                    Park.warn('v-vehicles: %s raised: %s', job.label, tostring(job.result[2]))
                end
            end
            job.done = true
        end
        working = false
    end)
end

local function enqueue(label, fn)
    tail = tail + 1
    local job = { label = label, fn = fn }
    jobs[tail] = job
    work()
    return job
end

--[[
    Queue a job and wait for it. A job that has not STARTED by the deadline is cancelled and
    answers 'busy'; one that has started is always waited for, because cancelling a spawn
    half way is how an entity ends up in the world with nothing pointing at it.
]]
local function runNow(label, fn, timeoutMs)
    local job = enqueue(label, fn)
    local deadline = Park.ticks() + (tonumber(timeoutMs) or 5000)

    while not job.done do
        if not job.started and Park.ticks() > deadline then
            job.cancelled = true
            return false, 'busy'
        end
        Wait(0)
    end

    if not job.result or not job.result[1] then return false, 'raised' end
    return true, table.unpack(job.result, 2, job.result.n)
end

--[[
    Plates whose garage or impound trip v-park itself started, until when. The unparked event it
    causes is ours, not a garage storing the car, and the despawn and the forgetting that follow
    have nothing left to do. A few seconds rather than "until the call returns": the removal
    that asked for it is still writing its own rows when the call does.
]]
local handing = {}
local HANDING_MS = 5000

local function hand(plate)
    handing[plate] = Park.ticks() + HANDING_MS
end

local function handed(plate)
    local until_ = plate and handing[plate]
    if not until_ then return false end
    if Park.ticks() > until_ then
        handing[plate] = nil
        return false
    end
    return true
end

-- plate -> the pose and condition last written through MarkParked, so a flush that changed
-- nothing about a car does not write its row again.
local pushed = {}

local function signature(record)
    return ('%.2f|%.2f|%.2f|%.1f|%d|%d|%d'):format(
        tonumber(record.pos_x) or 0, tonumber(record.pos_y) or 0, tonumber(record.pos_z) or 0,
        tonumber(record.rot_z) or 0,
        math.floor(tonumber(record.fuel) or -1),
        math.floor(tonumber(record.engine_health) or -1),
        math.floor(tonumber(record.body_health) or -1))
end

-- What v-vehicles keeps of a car's condition. v-park's own property table is NOT its `props`:
-- the two formats differ, and v-vehicles' props are what its garages and dealership read.
local function condition(record)
    return {
        fuel = tonumber(record.fuel),
        engine = tonumber(record.engine_health),
        body = tonumber(record.body_health),
        vehicleType = Classes and Classes.setterType and Classes.setterType(record.class, record.vehicle_type) or nil,
    }
end

local function poseOf(record)
    local x, y, z = tonumber(record.pos_x), tonumber(record.pos_y), tonumber(record.pos_z)
    if not (x and y and z) then return nil end
    return { x = x, y = y, z = z }, (tonumber(record.rot_z) or 0.0) % 360.0
end

-- Inside a job: write where the car stands, unless that is already what the row says.
local function markParked(record, force)
    local plate = record.plate
    local sig = signature(record)
    if not force and pushed[plate] == sig then return true end

    local at, heading = poseOf(record)
    if not at then return false end

    local ok, done, why = call('MarkParked', plate, at, heading, condition(record))
    if ok and done then
        pushed[plate] = sig
        return true
    end

    Park.debug('v-vehicles would not park %s: %s', tostring(plate), tostring(ok and why or 'no answer'))
    return false
end

-- ---------------------------------------------------------------------------------------
-- Garages
-- ---------------------------------------------------------------------------------------

local function garageList()
    if not Park.started('v-garages') then return {} end
    local list = Park.try(function() return exports['v-garages']:GetGarages() end)
    return type(list) == 'table' and list or {}
end

--[[
    The garage a car goes home to: the one asked for when v-garages has it, else the last one
    it came out of, else the first public garage. An impound lot is never a garage to go home
    to - v-garages lists only impounded cars there, so a car "stored" in it would be invisible.
]]
local function garageFor(wanted, fallback)
    local list = garageList()
    local function find(id)
        if type(id) ~= 'string' or id == '' then return nil end
        for _, garage in ipairs(list) do
            if garage.id == id then return garage end
        end
        return nil
    end

    local asked = find(wanted)
    if asked then return asked.id, asked.type == 'impound' end

    local previous = find(fallback)
    if previous and previous.type ~= 'impound' then return previous.id, false end

    for _, garage in ipairs(list) do
        if garage.type == 'public' then return garage.id, false end
    end

    return nil, false
end

-- Inside a job: off the street, into `state`, through the calls v-garages itself uses.
local function sendTo(plate, state, garage)
    hand(plate)

    if garage then call('SetGarage', plate, garage) end

    local done
    if isLive(plate) then
        done = select(2, call('DespawnOwned', plate, nil, state))
    else
        done = select(2, call('SetState', plate, state))
    end

    pushed[plate] = nil
    return done == true
end

-- ---------------------------------------------------------------------------------------
-- The adapter
-- ---------------------------------------------------------------------------------------

local function fullName(first, last)
    local name = ((first or '') .. ' ' .. (last or ''))
    name = name:gsub('^%s+', ''):gsub('%s+$', '')
    return name ~= '' and name or nil
end

Bridge.adapters.vcore = {
    resources = function()
        return { resourceName('vcore', 'v-core') }
    end,

    handshake = function(resource)
        local object = Park.try(function() return exports[resource]:GetCore() end)
        if type(object) == 'table' and Park.callable(object.GetPlayer) then return object end
        return nil
    end,

    -- nil until the character is chosen: v-core only knows a player once one is loaded.
    player = function(object, src)
        local found = Park.try(object.GetPlayer, src)
        return type(found) == 'table' and found or nil
    end,

    characterId = function(_, player)
        return player and player.citizenid or nil
    end,

    license = function(_, player)
        return player and player.license or nil
    end,

    name = function(_, player)
        if not player then return nil end
        local info = player.charinfo
        if type(info) == 'table' then
            local name = fullName(info.firstname, info.lastname)
            if name then return name end
        end
        return player.name
    end,

    offlineNames = {
        query = 'SELECT `citizenid` AS `id`, `firstname`, `lastname` FROM `characters` WHERE `citizenid` IN (%s)',
        read = function(found)
            return fullName(found.firstname, found.lastname)
        end,
    },

    job = function(_, player)
        local job = player and player.job
        if type(job) ~= 'table' or not job.name then return nil end

        -- Duty is v-jobs', and unset there means on duty.
        local onDuty = true
        if Park.started('v-jobs') then
            onDuty = Park.try(function() return exports['v-jobs']:IsOnDuty(player.source) end) ~= false
        end

        return { name = job.name, grade = tonumber(job.grade) or 0, boss = false, onDuty = onDuty }
    end,

    gang = function(_, player)
        local gang = player and player.gang
        if type(gang) ~= 'table' or not gang.name or gang.name == 'none' then return nil end
        return { name = gang.name, grade = tonumber(gang.grade) or 0 }
    end,

    --[[
        v-core's staff tiers. A name v-core does not know ranks as 0 there, the same as a plain
        user, so `HasPermission(src, 'god')` would answer yes for everybody: only the tiers it
        actually ranks above a user are asked.
    ]]
    hasGroup = function(object, src, groups)
        for _, group in ipairs(groups) do
            local rank = tonumber(Park.try(object.PermRank, group)) or 0
            if rank > 0 and Park.try(object.HasPermission, src, group) == true then return true end
        end
        return false
    end,

    -- Described for the panel and the messages. Nothing writes it with SQL on this framework:
    -- every write below goes through v-vehicles.
    ownedTable = function()
        return {
            table = 'character_vehicles',
            plate = 'plate',
            owner = 'citizenid',
            model = 'model',
            id = 'id',
            storedColumn = 'state',
            storedValue = STATE.GARAGED,
            outValue = STATE.OUT,
            garageColumn = 'garage',
        }
    end,
}

-- First: it is the framework this copy of v-park ships inside, and the only one that answers
-- on it. Config.Compat.framework still forces another one on a server that runs two.
table.insert(Bridge.order, 1, 'vcore')

-- ---------------------------------------------------------------------------------------
-- Owned vehicles, keys and garages on v-core. The upstream answer everywhere else.
-- ---------------------------------------------------------------------------------------

local upstream = {
    ownedByPlate = Bridge.ownedByPlate,
    isStored = Bridge.isStored,
    markOut = Bridge.markOut,
    returnToGarage = Bridge.returnToGarage,
    impound = Bridge.impound,
    keyProvider = Bridge.keyProvider,
    giveKeys = Bridge.giveKeys,
}

function Bridge.ownedByPlate(plate)
    if not active() then return upstream.ownedByPlate(plate) end

    local found = row(Park.plate(plate))
    if not found then return nil end

    return { owner = found.citizenid, id = found.id, stored = stateOf(found), garage = found.garage }
end

-- In a garage or the impound. A parked car is in the street, like one that is out.
function Bridge.isStored(found)
    if not active() then return upstream.isStored(found) end
    if type(found) ~= 'table' then return false end

    local state = tonumber(found.stored)
    return state == STATE.GARAGED or state == STATE.IMPOUND
end

-- Nothing to write: a car v-vehicles brings back with no player stays PARKED, and one a
-- player takes out of a garage is marked out by v-vehicles itself.
function Bridge.markOut(plate)
    if not active() then return upstream.markOut(plate) end
    return false
end

function Bridge.returnToGarage(plate, garage)
    if not active() then return upstream.returnToGarage(plate, garage) end
    if not (Config and Config.Garages and Config.Garages.returnToGarageOnRemoval) then return false end

    local normalised = Park.plate(plate)
    if not normalised then return false end

    local ok, done = runNow('garage ' .. normalised, function()
        local found = row(normalised)
        if not found then return false end

        -- Already off the street. An impounded car stays impounded: a removal is not a way out
        -- of the impound fee.
        local state = stateOf(found)
        if state == STATE.GARAGED or state == STATE.IMPOUND then return true end

        local target, isImpound = garageFor(garage, found.garage)
        if isImpound then return sendTo(normalised, STATE.IMPOUND, nil) end
        return sendTo(normalised, STATE.GARAGED, target)
    end)

    return ok and done == true
end

-- v-core has a real impound: v-garages' impound lot lists every impounded car.
function Bridge.impound(plate)
    if not active() then return upstream.impound(plate) end

    local normalised = Park.plate(plate)
    if not normalised then return false, 'none' end

    local ok, done = runNow('impound ' .. normalised, function()
        local found = row(normalised)
        if not found then return false end
        if stateOf(found) == STATE.IMPOUND then return true end
        return sendTo(normalised, STATE.IMPOUND, nil)
    end)

    if ok and done == true then return true, 'impound' end
    return false, 'none'
end

local function vehicleKeys()
    local force = Config and Config.Compat and Config.Compat.keys
    if force == 'none' then return false end
    if force and force ~= 'auto' and force ~= '' and force ~= VEHICLES then return false end
    return Park.started(VEHICLES)
end

function Bridge.keyProvider()
    if active() and vehicleKeys() then return VEHICLES end
    return upstream.keyProvider()
end

function Bridge.giveKeys(src, plate, netId)
    if not (active() and vehicleKeys()) then return upstream.giveKeys(src, plate, netId) end
    if not (Config and Config.Keys and Config.Keys.restore) then return false end

    local normalised = Park.plate(plate)
    if not normalised or type(src) ~= 'number' or src <= 0 then return false end

    local ok, given = call('GiveKeys', src, normalised)
    return ok and given == true
end

--[[
    The owner always has the keys on v-vehicles, and anybody handed a set this session. nil
    off v-core, so `Ownership.hasKeys` asks the upstream providers.
]]
function Bridge.hasKeys(src, plate)
    if not (active() and vehicleKeys()) then return nil end

    local normalised = Park.plate(plate)
    if not normalised then return false end

    local ok, has = call('HasKeys', src, normalised)
    return ok and has == true
end

-- ---------------------------------------------------------------------------------------
-- The parked car's life. Called from a handful of lines in the feature files.
-- ---------------------------------------------------------------------------------------

--[[
    May this vehicle be kept at all? Only a car `character_vehicles` knows, and that is in the
    street: v-park could never bring anything else back without creating it itself.
]]
function Bridge.mayPersist(plate)
    if not active() then return true end

    local found = row(Park.plate(plate))
    if not found then return false, 'refuse.not_registered' end

    local state = stateOf(found)
    if state == STATE.GARAGED or state == STATE.IMPOUND then return false, 'refuse.in_garage' end

    return true
end

--[[
    Put a parked car into the world. Called by `spawnEntity` in server/spawn.lua.

    Returns nil off v-core (the caller creates the entity itself), else `entity, true` - the
    restore goes through the server setter, which is not waited on - or `false, why`, where
    `why` is 'defer' for "try again later without counting it as a failure".
]]
local forget

function Bridge.spawnVehicle(record, lift)
    if not active() then return nil end

    local plate = record and record.plate
    if not plate then return false, 'it has no plate to ask v-vehicles about' end
    if not Park.started(VEHICLES) then return false, 'defer' end

    local entityConfig = (Config.Streaming and Config.Streaming.entity) or {}
    local culling = tonumber(entityConfig.cullingRadius) or 0

    local coords = { x = record.pos_x, y = record.pos_y, z = (record.pos_z or 0.0) + (tonumber(lift) or 0.0) }
    local opts = {
        rotation = { x = record.rot_x or 0.0, y = record.rot_y or 0.0, z = record.rot_z or 0.0 },
        bucket = record.bucket or 0,
        orphanMode = entityConfig.orphanMode == false and 0 or 2,
        cullingRadius = culling > 0 and culling or nil,
        vehicleType = Classes.setterType(record.class, record.vehicle_type),
    }

    local ok, netId, why = runNow('spawn ' .. plate, function()
        local id, err = select(2, call('SpawnOwned', nil, plate, coords, record.rot_z or 0.0, opts))

        --[[
            v-vehicles still holds an entity for this plate that v-park does not: a restart of
            v-park alone, whose reconcile sweep deleted the leftovers. v-park decides when a
            parked car is in the world, so that one goes and the car comes back once.
        ]]
        if not id and err == 'already' then
            call('DespawnOwned', plate)
            id, err = select(2, call('SpawnOwned', nil, plate, coords, record.rot_z or 0.0, opts))
        end

        return id, err
    end, 2000)

    if not ok then return false, 'defer' end

    if not netId then
        -- Not in the street any more as far as v-vehicles knows: stored, impounded, sold.
        if why == 'notparked' or why == 'unknown' then
            local reason = why == 'unknown' and 'not registered' or 'not parked'
            CreateThread(function() forget(record, reason) end)
            return false, 'defer'
        end
        return false, ('v-vehicles would not restore it (%s)'):format(tostring(why))
    end

    local entity = NetworkGetEntityFromNetworkId(netId)
    if not entity or entity == 0 then
        return false, 'v-vehicles answered with a network id that has no entity'
    end

    return entity, true
end

-- A player left it, or the server settled a new pose for it.
function Bridge.vehicleParked(record)
    if not active() or not (record and record.plate) then return end
    local id = record.id

    enqueue('park ' .. record.plate, function()
        local current = Store.get(id)
        if current and current.plate then markParked(current, true) end
    end)
end

-- Somebody got in to drive it: it is v-vehicles' ordinary car that is out until they leave it.
function Bridge.vehicleDriven(record)
    if not active() or not (record and record.plate) then return end
    local plate = record.plate

    enqueue('unpark ' .. plate, function()
        pushed[plate] = nil
        local ok, done, why = call('Unpark', plate)
        if ok and not done and why ~= 'notparked' then
            Park.debug('v-vehicles would not unpark %s: %s', plate, tostring(why))
        end
    end)
end

-- Rows v-park has just written. A car standing still has its row follow it; a car being
-- driven is OUT, and is parked again when somebody leaves it.
function Bridge.vehiclesSaved(records)
    if not active() or type(records) ~= 'table' then return end

    for _, record in ipairs(records) do
        if record.plate and pushed[record.plate] ~= signature(record) then
            local id = record.id
            enqueue('save ' .. record.plate, function()
                local current = Store.get(id)
                if current and current.plate and stateOf(row(current.plate)) == STATE.PARKED then
                    markParked(current, false)
                end
            end)
        end
    end
end

--[[
    v-park is taking the car out of the world (`Spawn.despawn`). It stays in the street: the row
    is parked where v-park last saw it, then v-vehicles lets go of the entity. A car that went
    to a garage or the impound meanwhile is left alone.
]]
function Bridge.vehicleStreamedOut(record)
    if not active() or not (record and record.plate) then return end
    local plate = record.plate
    if handed(plate) then return end

    local snapshot = {}
    for key, value in pairs(record) do snapshot[key] = value end

    enqueue('stream out ' .. plate, function()
        local state = stateOf(row(plate))
        if state ~= STATE.OUT and state ~= STATE.PARKED then return end

        local current = Store.get(snapshot.id) or snapshot
        markParked(current, state == STATE.OUT)
        call('DespawnOwned', plate)
    end)
end

--[[
    v-park stopped tracking the car (`Store.remove`). A car still in the world is an ordinary
    car that is out from now on; one that is not goes home to its garage rather than staying
    parked with nobody left to bring it back.
]]
function Bridge.vehicleForgotten(record)
    if not active() or not (record and record.plate) then return end
    local plate = record.plate
    pushed[plate] = nil
    if handed(plate) then return end

    local lastGarage = record.last_garage

    enqueue('forgotten ' .. plate, function()
        -- Back already: the plate was adopted again in the meantime.
        if Store.byPlate(plate) then return end

        local found = row(plate)
        if stateOf(found) ~= STATE.PARKED then return end

        if isLive(plate) then
            call('Unpark', plate)
        else
            local target = garageFor(lastGarage, found.garage)
            sendTo(plate, STATE.GARAGED, target)
        end
    end)
end

--[[
    Forget a record v-vehicles has taken off the street. Like an external delete: whatever took
    it there decided what happens to it, and v-park's row is only a stale cache now.
]]
forget = function(record, why)
    local current = record and Store.get(record.id)
    if not current then return end
    local plate = current.plate

    Park.log('%s (%s) is %s in v-vehicles - forgetting it', current.id, tostring(plate), tostring(why))

    if plate then hand(plate) end
    pcall(Spawn.despawn, current.id, 'v-vehicles: ' .. tostring(why))
    Store.remove(current.id)
    if plate then pushed[plate] = nil end

    if Database.available() then
        Database.thread(function()
            Database.execute(('DELETE FROM %s WHERE `id` = ?'):format(Database.table('vehicles')),
                { current.id })
        end)
    end
end

-- A garage or the impound took a parked car off the street: v-garages storing it, v-police
-- impounding it, an admin moving it with SetState. OUT is somebody driving it, and v-park keeps
-- following that car.
AddEventHandler('v-vehicles:server:unparked', function(plate, state)
    if not active() then return end
    state = tonumber(state)
    if state == STATE.OUT then return end

    local normalised = Park.plate(plate)
    if not normalised or handed(normalised) then return end

    local record = Store.byPlate(normalised)
    if not record then return end

    CreateThread(function()
        forget(record, state == STATE.IMPOUND and 'impounded' or 'in a garage')
    end)
end)

--[[
    What `GetVehicleByPlate` answers for a car v-vehicles has parked and v-park holds no row
    for - parked before v-park ran, or by another module. The same shape as a record of ours,
    without the fields only v-park knows (`id`, the full rotation, the timers).
]]
function Bridge.parkedRecord(plate)
    if not active() then return nil end

    local normalised = Park.plate(plate)
    local found = row(normalised)
    if not found or stateOf(found) ~= STATE.PARKED then return nil end

    local x, y, z = tonumber(found.park_x), tonumber(found.park_y), tonumber(found.park_z)
    if not (x and y and z) then return nil end

    local heading = (tonumber(found.park_heading) or 0.0) + 0.0
    local live = isLive(normalised)
    local netId
    if live then netId = select(3, call('GetEntity', normalised)) end

    local model = found.model
    local hash = type(model) == 'number' and model or GetHashKey(tostring(model or ''))

    return {
        plate = found.plate or normalised,
        model = hash,
        modelName = type(model) == 'string' and model or nil,
        owner = found.citizenid,
        ownerType = 'owned',
        ownerName = Bridge.displayName(found.citizenid, nil),
        coords = { x = x, y = y, z = z },
        rotation = { x = 0.0, y = 0.0, z = heading },
        heading = heading,
        bodyHealth = tonumber(found.body),
        engineHealth = tonumber(found.engine),
        fuel = tonumber(found.fuel),
        wrecked = (tonumber(found.engine) or 1000) <= 0,
        live = live,
        netId = netId,
        lastGarage = found.garage,
        source = VEHICLES,
    }
end

-- ---------------------------------------------------------------------------------------
-- The garages v-garages knows, for the auto-zones and the panel's "send to garage" list.
-- ---------------------------------------------------------------------------------------

table.insert(Bridge.garageReaders, 1, {
    resource = 'v-garages',
    read = function()
        local out = {}
        for _, garage in ipairs(garageList()) do
            -- The bay a retrieved car appears in, else the counter.
            local x = tonumber(garage.sx) or tonumber(garage.x)
            local y = tonumber(garage.sy) or tonumber(garage.y)
            local z = tonumber(garage.sz) or tonumber(garage.z)
            if x and y and z and type(garage.id) == 'string' then
                out[#out + 1] = { id = garage.id, label = garage.label or garage.id, point = Park.vec(x, y, z) }
            end
        end
        return out
    end,
})
