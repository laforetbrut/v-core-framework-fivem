-- A restore with nobody in scope yet: the server setter entity is registered at once and stays
-- out of the game world (DoesEntityExist false, world natives refused) until a client streams it.
-- The restore must succeed anyway, and leave exactly one entity.
-- Author: vyrriox.
local S = Config.State
local function eq(a, b, msg) if a ~= b then error(('%s: expected %s, got %s'):format(msg, tostring(b), tostring(a)), 2) end end
local function ok(c, msg) if not c then error(msg, 2) end end
local E = function(name) return H.exports[name] end

H.load()
H.step(1000)
H.orphanedSetter = true
H.addRow({ plate = 'VR00042', state = S.OUT })
ok(H.run(E('MarkParked'), 'VR00042', vector3(100, 200, 30), 90.0), 'mark parked')

local net, err = H.run(E('SpawnOwned'), nil, 'VR00042', nil, nil, { rotation = vector3(1, 2, 90), bucket = 0 })
ok(net, 'a restore nobody can see yet must not fail: ' .. tostring(err))
local count, id = 0, nil
for k, x in pairs(H.entities) do if x.alive and x.plate == 'VR00042' then count = count + 1; id = k end end
eq(count, 1, 'one entity, plated')
eq(H.entities[id].how, 'setter', 'through the setter')
eq(H.entities[id].orphan, 2, 'kept while nobody is near')
eq(H.run(E('IsLive'), 'VR00042'), true, 'in the live index')
eq(H.row('VR00042').state, S.PARKED, 'still parked')
eq(select(2, H.run(E('SpawnOwned'), nil, 'VR00042')), 'already', 'no second copy')

-- a client streams it in: the entity is now readable
H.entities[id].streamed = true
eq(H.run(E('GetEntity'), 'VR00042'), id, 'GetEntity once streamed')
print('PASS restore-orphaned')
