-- v-park on v-core, end to end: every parked car comes out of v-vehicles' SpawnOwned and v-park
-- never calls a vehicle-creating native; the row in `character_vehicles` follows the car; a car
-- v-garages stores is forgotten; GetVehicleByPlate answers for a car v-vehicles parked.
-- Author: vyrriox.
local S = { OUT = 0, GARAGED = 1, IMPOUND = 2, PARKED = 3 }
local function eq(a, b, msg) if a ~= b then error(('%s: expected %s, got %s'):format(msg, tostring(b), tostring(a)), 2) end end
local function ok(c, msg) if not c then error(msg, 2) end end
local function VVX(m) return H.res['v-vehicles'].exports[m] end
local function VPX(m) return H.res['v-park'].exports[m] end

H.orphanedSetter = true
H.boot()
local VP = H.VP
eq(VP.Bridge.kind(), 'vcore', 'v-core is detected first')
eq(VP.Bridge.keyProvider(), 'v-vehicles', 'keys come from v-vehicles')
eq(VP.Runtime.garageResource(), 'v-garages', 'garages are read from v-garages')
print('boot ok: vcore adapter, v-vehicles keys, v-garages zones')

-- Answer every restore instruction the way the placing client does, and stream the entity in.
local answered = 0
local function answerRestores()
    for i = answered + 1, #H.client do
        local c = H.client[i]
        if c.name == 'vpark:client:restore' then
            local e = NetworkGetEntityFromNetworkId(c.args[1])
            if e ~= 0 then H.entities[e].streamed = true end
            local id = H.bags[e] and H.bags[e]['vpark:id']
            if id then H.fromClient(c.target, 'vpark:server:restored', id, { ok = true, dressed = true, frozen = true }) end
        end
    end
    answered = #H.client
end
local function settle(ms)
    local t = 0
    while t < ms do H.step(500); answerRestores(); t = t + 500 end
end

-- ── A. a car taken out of its garage and left in the street is kept, and parked ──
H.addRow({ plate = 'VR10001', citizenid = 'CID1', model = 'sultan', state = S.GARAGED, garage = 'legion' })
H.addPlayer(1, 'CID1', vector3(500.0, 500.0, 30.0))
settle(2000)
local net = H.run(VVX('SpawnOwned'), 1, 'VR10001', vector3(505.0, 500.0, 30.0), 90.0)
ok(net, 'the player takes it out')
local first = NetworkGetEntityFromNetworkId(net)
H.fromClient(1, 'vpark:server:candidate', {
    model = GetHashKey('sultan'), modelName = 'SULTAN', plate = 'VR10001 ', netId = net, class = 4,
    position = { x = 505.0, y = 500.0, z = 30.0 }, rotation = { x = 0.0, y = 0.0, z = 90.0 },
    properties = { fuelLevel = 63.0, bodyHealth = 990.0, engineHealth = 980.0 },
})
settle(2000)
local rec = VP.Store.byPlate('VR10001')
ok(rec, 'kept by v-park')
eq(rec.owner, 'CID1', 'owner read from character_vehicles')
eq(rec.owner_type, 'owned', 'an owned car')
eq(H.row('VR10001').state, S.PARKED, 'parked in v-vehicles')
eq(H.row('VR10001').park_x, 505.0, 'where it was left')
eq(H.row('VR10001').fuel, 63, 'fuel written through MarkParked')

-- an ambient car is not kept: there would be no row to bring it back from
H.nextEnt, H.nextNet = H.nextEnt + 1, H.nextNet + 1
H.entities[H.nextEnt] = { id = H.nextEnt, net = H.nextNet, model = GetHashKey('blista'), pos = vector3(510.0, 500.0, 30.0),
                          heading = 0.0, plate = 'NPC12345', how = 'ambient', alive = true }
H.fromClient(1, 'vpark:server:candidate', {
    model = GetHashKey('blista'), modelName = 'BLISTA', plate = 'NPC12345', netId = H.nextNet, class = 0,
    position = { x = 510.0, y = 500.0, z = 30.0 }, rotation = { x = 0.0, y = 0.0, z = 0.0 }, properties = {},
})
settle(1000)
eq(VP.Store.byPlate('NPC12345'), nil, 'an unregistered car is refused')
eq(VP.Persist.refusals()[1] and VP.Persist.refusals()[#VP.Persist.refusals()].reason, 'refuse.not_registered', 'with its reason')
print('A ok: adopted and parked through MarkParked, ambient car refused')

-- ── B. the player walks away: streamed out, still parked ──
H.movePlayer(1, vector3(3000.0, 3000.0, 30.0))
settle(30000)
ok(not VP.Store.isLive(rec.id), 'streamed out by v-park')
eq(H.row('VR10001').state, S.PARKED, 'the row stays parked')
eq(H.run(VVX('IsLive'), 'VR10001'), false, 'v-vehicles let go of the entity')
ok(not H.entities[first].alive, 'the entity is gone')
print('B ok: streamed out through DespawnOwned')

-- ── C. back near it: it comes back through SpawnOwned, never through v-park ──
local before = H.creates['v-vehicles'] or 0
H.movePlayer(1, vector3(500.0, 500.0, 30.0))
settle(30000)
local entry = VP.Store.live(rec.id)
ok(entry and entry.entity, 'restored by v-park')
eq(H.creates['v-park'] or 0, 0, 'v-park never called CreateVehicle or CreateVehicleServerSetter')
eq((H.creates['v-vehicles'] or 0) - before, 1, 'v-vehicles created it, once')
local e = H.entities[entry.entity]
eq(e.how, 'setter', 'through the server setter')
eq(e.plate, 'VR10001', 'with its plate')
eq(H.bags[entry.entity]['vpark:id'], rec.id, 'identified as ours')
eq(H.run(VVX('IsLive'), 'VR10001'), true, 'in v-vehicles live index')
eq(H.row('VR10001').state, S.PARKED, 'still parked after the restore')
local alive = 0
for _, x in pairs(H.entities) do if x.alive and x.plate == 'VR10001' then alive = alive + 1 end end
eq(alive, 1, 'exactly one VR10001 in the world')
print('C ok: restored through SpawnOwned only')

-- ── C2. v-vehicles still holds an entity v-park lost track of (v-park restarted alone, and its
--        reconcile sweep deleted the leftover): the car comes back at once, and only once ──
local answers = {}
local spawnOwned = H.res['v-vehicles'].exports.SpawnOwned
H.res['v-vehicles'].exports.SpawnOwned = function(...)
    local id, err = spawnOwned(...)
    answers[#answers + 1] = err or 'ok'
    return id, err
end
H.entities[entry.entity].alive = false
VP.Store.setLive(rec.id, nil)
settle(5000)
H.res['v-vehicles'].exports.SpawnOwned = spawnOwned
eq(answers[1], 'already', 'v-vehicles first answered that it still had one')
eq(answers[2], 'ok', 'then restored it once its stale entry was let go')
entry = VP.Store.live(rec.id)
ok(entry and entry.entity and H.entities[entry.entity].alive, 'back in the world')
alive = 0
for _, x in pairs(H.entities) do if x.alive and x.plate == 'VR10001' then alive = alive + 1 end end
eq(alive, 1, 'still exactly one VR10001')
eq(H.creates['v-park'] or 0, 0, 'still nothing created by v-park')
print('C2 ok: a stale entity in v-vehicles is replaced, not duplicated')

-- ── D. GetVehicleByPlate, for our row and for a car only v-vehicles knows ──
local mine = H.run(VPX('GetVehicleByPlate'), 'VR10001')
ok(mine and mine.coords, 'our record')
eq(mine.coords.x, 505.0, 'our record coords')
H.addRow({ plate = 'VR10002', citizenid = 'CID2', model = 'kuruma', state = S.OUT, garage = 'legion' })
ok(H.run(VVX('MarkParked'), 'VR10002', vector3(-1200.5, -300.25, 37.0), 45.0), 'parked by another module')
local theirs = H.run(VPX('GetVehicleByPlate'), 'VR10002')
ok(theirs and theirs.coords, 'GetVehicleByPlate answers for a car v-vehicles parked')
eq(theirs.coords.x, -1200.5, 'x'); eq(theirs.coords.y, -300.25, 'y'); eq(theirs.coords.z, 37.0, 'z')
eq(theirs.heading, 45.0, 'heading'); eq(theirs.owner, 'CID2', 'owner'); eq(theirs.live, false, 'not in the world')
eq(H.run(VPX('GetVehicleByPlate'), 'VR99999'), nil, 'an unknown plate')
print('D ok: GetVehicleByPlate')

-- ── E. getting in and driving off unparks it, leaving it parks it again ──
H.fromClient(1, 'vpark:server:touched', rec.id, true)
settle(1000)
eq(H.row('VR10001').state, S.OUT, 'driven: an ordinary car that is out')
H.entities[entry.entity].pos = vector3(520.0, 505.0, 30.5)
H.fromClient(1, 'vpark:server:parked', rec.id, { x = 520.0, y = 505.0, z = 30.5 }, { x = 0.0, y = 0.0, z = 180.0 })
settle(1000)
eq(H.row('VR10001').state, S.PARKED, 'left: parked again')
eq(H.row('VR10001').park_x, 520.0, 'at the new spot')
eq(H.row('VR10001').park_heading, 180.0, 'facing the new way')
print('E ok: Unpark on entry, MarkParked on exit')

-- ── F. v-garages stores it: v-park forgets it, and does not bring it back ──
ok(H.run(VVX('DespawnOwned'), 'VR10001', nil, S.GARAGED), 'stored the way v-garages does')
settle(2000)
eq(VP.Store.byPlate('VR10001'), nil, 'v-park forgot it')
eq(H.row('VR10001').state, S.GARAGED, 'in the garage')
settle(10000)
for _, x in pairs(H.entities) do ok(not (x.alive and x.plate == 'VR10001'), 'nothing brought back') end
print('F ok: a stored car is forgotten')

-- ── G. a v-park row whose car is no longer parked is dropped, not created ──
VP.Store.add({ id = 'STALE0001', plate = 'VR10003', model = GetHashKey('sultan'), model_name = 'SULTAN', class = 4,
    owner = 'CID1', owner_type = 'owned', pos_x = 502.0, pos_y = 498.0, pos_z = 30.0, rot_x = 0.0, rot_y = 0.0,
    rot_z = 0.0, bucket = 0, properties = {}, created_at = os.time(), updated_at = os.time(), touched_at = os.time(),
    last_used_at = os.time(), offline_secs = 0, rental_until = 0 }, false)
H.addRow({ plate = 'VR10003', citizenid = 'CID1', model = 'sultan', state = S.GARAGED, garage = 'legion' })
settle(15000)
eq(VP.Store.get('STALE0001'), nil, 'the stale row is dropped')
eq(H.row('VR10003').state, S.GARAGED, 'the garaged car stays in its garage')
eq(H.creates['v-park'] or 0, 0, 'and nothing was created for it')
print('G ok: a stale row is dropped')

-- ── H. v-park expires a car: it goes home to its garage ──
H.addRow({ plate = 'VR10004', citizenid = 'CID1', model = 'sultan', state = S.OUT, garage = 'legion' })
H.run(VVX('MarkParked'), 'VR10004', vector3(4000.0, 4000.0, 30.0), 0.0)
VP.Store.add({ id = 'EXPIRE001', plate = 'VR10004', model = GetHashKey('sultan'), model_name = 'SULTAN', class = 4,
    owner = 'CID1', owner_type = 'owned', pos_x = 4000.0, pos_y = 4000.0, pos_z = 30.0, rot_x = 0.0, rot_y = 0.0,
    rot_z = 0.0, bucket = 0, properties = {}, created_at = os.time(), updated_at = os.time(), touched_at = os.time(),
    last_used_at = os.time(), offline_secs = 0, rental_until = 0, last_garage = 'legion' }, false)
local removed, outcome = H.run(VP.Lifecycle.remove, 'EXPIRE001', 'garage', 'selftest', 'expired')
ok(removed, 'removed')
eq(outcome, 'returned', 'returned to the garage')
settle(2000)
eq(H.row('VR10004').state, S.GARAGED, 'in its garage'); eq(H.row('VR10004').garage, 'legion', 'the garage it knew')
eq(H.row('VR10004').park_x, nil, 'the street position is forgotten')
local impounded, how = H.run(VP.Bridge.impound, 'VR10002')
ok(impounded, 'impound'); eq(how, 'impound', 'a real impound on v-core')
eq(H.row('VR10002').state, S.IMPOUND, 'in the impound lot')
print('H ok: expiry and impound go through v-vehicles')

eq(H.creates['v-park'] or 0, 0, 'v-park never created a vehicle in the whole run')
print(('PASS vcore (%d vehicle(s) created, all by v-vehicles)'):format(H.creates['v-vehicles'] or 0))
