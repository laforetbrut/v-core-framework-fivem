-- The parked-car rules of v-vehicles, end to end, and the non-parked path unchanged.
-- Author: vyrriox.
local S = Config.State
local function eq(a, b, msg) if a ~= b then error(('%s: expected %s, got %s'):format(msg, tostring(b), tostring(a)), 2) end end
local function ok(c, msg) if not c then error(msg, 2) end end
local function ent(netid) return NetworkGetEntityFromNetworkId(netid) end
local E = function(name) return H.exports[name] end

-- ── A. the non-parked path, before the migration has run ─────
H.resState.oxmysql = 'stopped'
H.load()
H.players[1] = { citizenid = 'CID1' }
H.addRow({ plate = 'VR00001', state = S.GARAGED })
H.addRow({ plate = 'VR00002', state = S.GARAGED })
H.addRow({ plate = 'VR00003', state = S.GARAGED })
ok(not H.cols.park_x, 'columns must not exist yet')

local net, err = H.run(E('SpawnOwned'), 1, 'VR00001', vector3(1, 2, 3), 90.0)
ok(net, 'player spawn failed: ' .. tostring(err))
eq(H.row('VR00001').state, S.OUT, 'player spawn sets OUT')
eq(H.entities[ent(net)].how, 'rpc', 'player spawn keeps the RPC CreateVehicle')
eq(H.entities[ent(net)].orphan, nil, 'player spawn sets no orphan mode')
eq(H.client[#H.client].name, 'v-vehicles:client:applyState', 'player spawn dresses through the client')
eq(H.client[#H.client].target, 1, 'dressed by the player')
eq(select(2, H.run(E('SpawnOwned'), nil, 'VR00002')), 'notparked', 'restore refuses a garaged car')
eq(select(2, H.run(E('SpawnOwned'), 1, 'VR00001', vector3(1, 2, 3), 0)), 'already', 'no second copy')
ok(H.run(E('DespawnOwned'), 'VR00001', nil, S.GARAGED), 'despawn')
eq(H.row('VR00001').state, S.GARAGED, 'despawn to garage')
local net1 = H.run(E('SpawnOwned'), 1, 'VR00001', vector3(1, 2, 3), 0)
H.entities[ent(net1)].alive = false
H.step(31000)
eq(H.row('VR00001').state, S.IMPOUND, 'a vanished car that was out goes to the impound')
ok(not H.run(E('IsLive'), 'VR00001'), 'and leaves the live index')
print('A ok: non-parked path unchanged, no park column needed')

-- ── B. boot migration ────────────────────────────────────────
H.resState.oxmysql = 'started'
H.step(1000)
for _, c in ipairs({ 'park_x', 'park_y', 'park_z', 'park_heading', 'vehicle_type', 'parked_at' }) do
    ok(H.cols[c], 'migration must add ' .. c)
end
print('B ok: migration added the six columns')

-- ── C. parking a car that is out ─────────────────────────────
local net2 = H.run(E('SpawnOwned'), 1, 'VR00002', vector3(10, 20, 30), 45.0)
H.entities[ent(net2)].kind = 'bike'
H.entities[ent(net2)].pos = vector3(11, 21, 31)
H.entities[ent(net2)].heading = 370.0
eq(H.run(E('MarkParked'), 'VR00002 ', nil, nil, { fuel = 150, engine = 500 }), true, 'mark parked')
local r = H.row('VR00002')
eq(r.state, S.PARKED, 'state PARKED')
eq(r.park_x, 11.0, 'x from the entity'); eq(r.park_z, 31.0, 'z from the entity')
eq(r.park_heading, 10.0, 'heading normalised')
eq(r.vehicle_type, 'bike', 'vehicle type from the entity')
eq(r.fuel, 100, 'fuel clamped'); eq(r.engine, 500, 'engine kept')
eq(#H.firedNamed('v-vehicles:server:parked'), 1, 'parked event')
eq(select(2, H.run(E('MarkParked'), 'VR00003', vector3(1, 1, 1), 0)), 'stored', 'a garaged car cannot be parked')
eq(select(2, H.run(E('MarkParked'), 'VR00002', { x = 'a' }, 0)), 'coords', 'bad coords refused')
eq(select(2, H.run(E('MarkParked'), 'NOPE', vector3(1, 1, 1), 0)), 'unknown', 'unknown plate')
eq(select(2, H.exports.SetState('VR00002', S.PARKED)), 'usemarkparked', 'SetState cannot park')

-- ── D. the entity vanishes: no impound ───────────────────────
H.entities[ent(net2)].alive = false
H.step(31000)
eq(H.row('VR00002').state, S.PARKED, 'a vanished parked car stays parked')
eq(H.row('VR00002').park_x, 11.0, 'and keeps its position')
ok(not H.run(E('IsLive'), 'VR00002'), 'but leaves the live index')

-- ── E. restore without a player ──────────────────────────────
local before = #H.client
local net3, e3 = H.run(E('SpawnOwned'), nil, 'VR00002')
ok(net3, 'restore failed: ' .. tostring(e3))
local e = H.entities[ent(net3)]
eq(e.how, 'setter', 'restore uses the server setter')
eq(e.kind, 'bike', 'with the stored type')
eq(e.pos.x, 11.0, 'at the stored position'); eq(e.heading, 10.0, 'with the stored heading')
eq(e.orphan, 2, 'kept when nobody is near')
eq(e.plate, 'VR00002', 'plated')
eq(H.row('VR00002').state, S.PARKED, 'still parked after the restore')
eq(#H.client, before, 'no client event without a player')
local sp = H.firedNamed('v-vehicles:server:spawned')
eq(sp[#sp].args[1], nil, 'spawned event carries a nil source')
eq(sp[#sp].args[2], 'VR00002', 'spawned event carries the plate')
local g, gn = H.run(E('GetEntity'), 'VR00002')
eq(g, ent(net3), 'GetEntity'); eq(gn, net3, 'GetEntity netid')
eq(H.run(E('GetPlateOwner'), 'VR00002'), 'CID1', 'GetPlateOwner')
eq(H.run(E('GetEntity'), 'VR00003'), nil, 'GetEntity of a car not in the world')
local list = H.run(E('GetParked'))
eq(#list, 1, 'one parked'); eq(list[1].plate, 'VR00002', 'parked plate')
eq(list[1].coords.y, 21.0, 'parked coords'); eq(list[1].live, true, 'parked live')
eq(#H.run(E('GetParked'), 'CID2'), 0, 'filtered by owner')
eq(#H.run(E('GetParked'), 'CID1'), 1, 'owner filter')
local opts = { rotation = vector3(5, 6, 7), bucket = 3, orphanMode = 0, cullingRadius = 300 }
H.run(E('DespawnOwned'), 'VR00002')
eq(H.row('VR00002').state, S.PARKED, 'streamed out, still parked')
local net4 = H.run(E('SpawnOwned'), nil, 'VR00002', vector3(12, 22, 32), 15.0, opts)
local e4 = H.entities[ent(net4)]
eq(e4.rot[3], 7.0, 'rotation applied'); eq(e4.bucket, 3, 'bucket'); eq(e4.orphan, 0, 'explicit orphan mode')
eq(e4.culling, 300.0, 'culling radius')

-- ── F. resource stop, then a restart of this resource alone ──
local net5 = H.run(E('SpawnOwned'), 1, 'VR00003', vector3(0, 0, 0), 0)
for _, fn in ipairs(H.events.onResourceStop) do H.run(fn, 'v-vehicles') end
ok(DoesEntityExist(ent(net4)), 'parked entity survives the stop')
eq(H.row('VR00002').state, S.PARKED, 'parked row survives the stop')
ok(not DoesEntityExist(ent(net5)) and ent(net5) == 0, 'a car that was out is deleted')
eq(H.row('VR00003').state, S.GARAGED, 'and goes back to its garage')

H.threads, H.events, H.exports = {}, {}, {}
H.load()
H.step(1000)
eq(H.run(E('IsLive'), 'VR00002'), true, 'restart adopts the parked car still in the world')
eq(select(2, H.run(E('SpawnOwned'), nil, 'VR00002')), 'already', 'so a restore makes no duplicate')
local alive = 0
for _, x in pairs(H.entities) do if x.alive and x.plate == 'VR00002' then alive = alive + 1 end end
eq(alive, 1, 'exactly one VR00002 in the world')

-- ── G. leaving the street ────────────────────────────────────
eq(H.run(E('Unpark'), 'VR00002'), true, 'unpark')
r = H.row('VR00002')
eq(r.state, S.OUT, 'unparked is OUT'); eq(r.park_x, nil, 'position forgotten'); eq(r.vehicle_type, 'bike', 'type kept')
eq(#H.firedNamed('v-vehicles:server:unparked'), 1, 'unparked event')
eq(select(2, H.run(E('Unpark'), 'VR00002')), 'notparked', 'unpark twice')
eq(select(2, H.run(E('DespawnOwned'), 'VR00002', nil, S.PARKED)), 'notparked', 'cannot despawn into PARKED')
H.run(E('MarkParked'), 'VR00002', vector3(50, 60, 70), 180)
H.run(E('DespawnOwned'), 'VR00002', nil, S.IMPOUND)   -- what v-police does
r = H.row('VR00002')
eq(r.state, S.IMPOUND, 'impounded from the street'); eq(r.park_x, nil, 'position forgotten on impound')
eq(#H.firedNamed('v-vehicles:server:unparked'), 2, 'unparked on impound')
eq(select(2, H.run(E('Unpark'), 'VR00002')), 'notlive', 'unpark needs the car in the world')

-- a parked car not in the world, sent to the garage by an admin
H.addRow({ plate = 'VR00009', state = S.OUT })
H.run(E('MarkParked'), 'VR00009', vector3(1, 2, 3), 0)
eq(H.exports.SetState('VR00009', S.GARAGED), true, 'SetState out of the street')
eq(H.row('VR00009').park_x, nil, 'SetState forgets the position')
print('C-G ok: parked cars survive vanishing, restore, stop and restart; leaving the street clears them')

-- every statement went through the fake database: none of them was unknown to it
print(('PASS parked (%d SQL statements)'):format(#H.sql))
