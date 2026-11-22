-- v-park without v-core: the bridge stands aside and v-park creates its own vehicles, as it does
-- upstream. Also the proof that the creation count in the harness can see v-park doing it.
-- Author: vyrriox.
local function eq(a, b, msg) if a ~= b then error(('%s: expected %s, got %s'):format(msg, tostring(b), tostring(a)), 2) end end
local function ok(c, msg) if not c then error(msg, 2) end end
local function VPX(m) return H.res['v-park'].exports[m] end

H.started['v-core'] = nil
H.boot()
local VP = H.VP
eq(VP.Bridge.kind(), 'standalone', 'no framework without v-core')
eq(VP.Bridge.isVCore(), false, 'the vcore bridge stands aside')
eq(VP.Bridge.spawnVehicle({ plate = 'X' }), nil, 'and does not answer for the spawn')

H.addPlayer(1, 'CID1', vector3(500.0, 500.0, 30.0))
VP.Store.add({ id = 'UPSTREAM1', plate = 'UP000001', model = GetHashKey('sultan'), model_name = 'SULTAN', class = 4,
    owner = 'license:CID1', owner_type = 'player', pos_x = 505.0, pos_y = 500.0, pos_z = 30.0, rot_x = 0.0,
    rot_y = 0.0, rot_z = 0.0, bucket = 0, properties = {}, created_at = os.time(), updated_at = os.time(),
    touched_at = os.time(), last_used_at = os.time(), offline_secs = 0, rental_until = 0 }, false)
H.step(10000)
ok(VP.Store.live('UPSTREAM1'), 'restored')
eq(H.creates['v-park'], 1, 'by v-park itself, through its own native call')

-- GetVehicleByPlate is the upstream one: v-vehicles is not asked
H.addRow({ plate = 'VR20001', citizenid = 'CID1', model = 'kuruma', state = 0 })
H.run(H.res['v-vehicles'].exports.MarkParked, 'VR20001', vector3(1.0, 2.0, 3.0), 0.0)
eq(H.run(VPX('GetVehicleByPlate'), 'VR20001'), nil, 'no v-vehicles fallback off v-core')
ok(H.run(VPX('GetVehicleByPlate'), 'UP000001'), 'its own rows still answer')
print('PASS upstream (v-park created its own vehicle off v-core)')
