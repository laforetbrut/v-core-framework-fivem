-- Runs v-park's server scripts and v-vehicles' server script side by side outside the game,
-- each in an environment of its own, the way FiveM gives every resource its own Lua state.
-- Built on tools/vehicles-selftest/stubs.lua: its scheduler, entities and in-memory
-- `character_vehicles` are the ones v-vehicles' own selftest already trusts.
-- Author: vyrriox.

dofile(STUBS)

-- A thread polling with Wait(0) must still let virtual time pass, as a server tick does.
function Wait(ms) coroutine.yield(math.max(1, tonumber(ms) or 0)) end

-- ── resources ─────────────────────────────────────────────────
H.started = { ['v-core'] = true, ['v-vehicles'] = true, ['v-garages'] = true, ['v-park'] = true,
              ['oxmysql'] = true, ['v-fuel'] = true, ['v-notify'] = true, ['v-jobs'] = true }
function GetResourceState(name) return H.started[name] and 'started' or 'missing' end

H.res = {}
local function resource(name)
    H.res[name] = H.res[name] or { exports = {} }
    return H.res[name]
end

-- ── v-core, v-garages and v-jobs, as far as v-park and v-vehicles ask them anything ──
local RANKS = { user = 0, mod = 1, admin = 2, superadmin = 3 }
H.vcore = {
    GetPlayer = function(src) return H.players[tonumber(src)] end,
    PermRank = function(level) return RANKS[level or 'user'] or 0 end,
    HasPermission = function(src, needed)
        local p = H.players[tonumber(src)]
        return (RANKS[p and p.permission or 'user'] or 0) >= (RANKS[needed or 'admin'] or 0)
    end,
    RegisterCallback = function(name, fn) H.callbacks[name] = fn end,
    GetSetting = function(_, _, def) return def end,
    RegisterModule = function() end,
    Log = function() end,
    Notify = function() end,
}
resource('v-core').exports.GetCore = function() return H.vcore end

H.garages = {
    { id = 'legion', label = 'Legion Square Parking', type = 'public', x = 215.9, y = -809.4, z = 30.7,
      sx = 228.1, sy = -800.2, sz = 30.6, sh = 158.0 },
    { id = 'impound', label = 'City Impound Lot', type = 'impound', x = 408.9, y = -1622.9, z = 29.3,
      sx = 401.6, sy = -1630.2, sz = 29.3, sh = 230.0 },
}
resource('v-garages').exports.GetGarages = function() return H.garages end
resource('v-jobs').exports.IsOnDuty = function() return true end

local function exportsFor(owner)
    return setmetatable({}, {
        __call = function(_, name, fn) resource(owner).exports[name] = fn end,
        __index = function(_, res)
            return setmetatable({}, { __index = function(_, method)
                return function(_, ...)
                    local fn = resource(res).exports[method]
                    if not fn then error(('No such export %s in resource %s'):format(method, res)) end
                    return fn(...)
                end
            end })
        end,
    })
end

-- Who called the natives that create a vehicle. The proof this selftest exists for.
H.creates = {}
local function counted(owner, fn)
    return function(...)
        H.creates[owner] = (H.creates[owner] or 0) + 1
        return fn(...)
    end
end

function H.env(name)
    local env = {
        exports = exportsFor(name),
        GetCurrentResourceName = function() return name end,
        CreateVehicle = counted(name, CreateVehicle),
        CreateVehicleServerSetter = counted(name, CreateVehicleServerSetter),
    }
    env._G = env
    return setmetatable(env, { __index = _G })
end

function H.loadInto(env, path)
    local chunk, err = loadfile(path, 't', env)
    if not chunk then error(err, 0) end
    chunk()
end

--- The Lua files a manifest block lists, in order.
function H.manifest(dir, block)
    local f = assert(io.open(dir .. '/fxmanifest.lua', 'r'))
    local text = f:read('a')
    f:close()
    local body = assert(text:match(block .. '%s*{(.-)\n}'), 'no ' .. block .. ' in the manifest')
    local out = {}
    for line in body:gmatch('[^\n]+') do
        local file = line:match("^%s*'([^']+%.lua)'")
        if file and not file:find('^@') then out[#out + 1] = dir .. '/' .. file end
    end
    return out
end

-- ── the natives v-park reaches on the server ──────────────────
function IsDuplicityVersion() return true end
function GetConvar(name, def) if name == 'onesync' then return 'on' end return def end
function GetGameTimer() return H.now end
function SetTimeout(ms, fn) CreateThread(function() Wait(ms) fn() end) end
function GetInvokingResource() return nil end
function GetResourceMetadata() return 'selftest' end
function PerformHttpRequest() end
H.commands = {}
function RegisterCommand(name, fn) H.commands[name] = fn end
function IsPlayerAceAllowed() return false end

H.bags = {}
function Entity(e)
    H.bags[e] = H.bags[e] or {}
    local bag = H.bags[e]
    return { state = setmetatable({}, { __index = function(_, k)
        if k == 'set' then return function(_, key, value) bag[key] = value end end
        return bag[k]
    end }) }
end

H.peds = {}
function H.addPlayer(src, cid, pos)
    H.players[src] = { source = src, citizenid = cid, license = 'license:' .. cid, name = 'Test ' .. cid,
                       charinfo = { firstname = 'Test', lastname = cid },
                       job = { name = 'unemployed', grade = 0 }, gang = { name = 'none', grade = 0 } }
    H.nextEnt = H.nextEnt + 1
    H.entities[H.nextEnt] = { id = H.nextEnt, net = 0, how = 'ped', pos = pos, heading = 0.0, alive = true }
    H.peds[src] = H.nextEnt
end
function H.movePlayer(src, pos) H.entities[H.peds[src]].pos = pos end
function GetPlayers()
    local out = {}
    for src in pairs(H.players) do out[#out + 1] = tostring(src) end
    table.sort(out)
    return out
end
function GetPlayerPed(src) return H.peds[tonumber(src)] or 0 end
function GetPlayerRoutingBucket() return 0 end
function GetPlayerPing() return 40 end
function GetPlayerIdentifiers(src)
    local p = H.players[tonumber(src)]
    return p and { p.license } or {}
end
function GetPlayerName(src) return H.players[tonumber(src)] and ('Player' .. tostring(src)) or nil end
function GetVehiclePedIsIn() return 0 end
function GetPedInVehicleSeat() return 0 end

local function world(e)
    if H.orphaned(e) then error('Tried to access invalid entity: ' .. tostring(e)) end
    return assert(H.entities[e], 'no entity ' .. tostring(e))
end
function SetEntityCoords(e, x, y, z) world(e).pos = vector3(x, y, z) end
function GetEntityRotation(e)
    local x = world(e)
    local r = x.rot or { 0.0, 0.0, x.heading or 0.0 }
    return vector3(r[1] or 0.0, r[2] or 0.0, r[3] or 0.0)
end
function GetEntityRoutingBucket(e) return world(e).bucket or 0 end

-- Vehicles only: the peds above are entities too, and a plate read on one would raise.
function GetAllVehicles()
    local out = {}
    for id, e in pairs(H.entities) do if e.alive and e.how ~= 'ped' then out[#out + 1] = id end end
    table.sort(out)
    return out
end

--- Deliver a client's net event to whichever resource registered it.
function H.fromClient(src, name, ...)
    local fn = assert(H.net[name], 'no net handler ' .. name)
    local args = table.pack(...)
    return H.run(function()
        _G.source = src
        local ok, err = pcall(fn, table.unpack(args, 1, args.n))
        _G.source = nil
        if not ok then error(err, 0) end
    end)
end

-- ── the two resources ─────────────────────────────────────────
function H.boot(opts)
    opts = opts or {}

    H.VV = H.env('v-vehicles')
    H.loadInto(H.VV, VV_DIR .. '/config.lua')
    H.loadInto(H.VV, VV_DIR .. '/server/main.lua')

    H.VP = H.env('v-park')
    -- v-park keeps its rows in memory here: its own SQL is not what this test is about, and the
    -- fake database only speaks `character_vehicles`.
    rawset(H.VP, 'MySQL', false)
    for _, path in ipairs(H.manifest(VP_DIR, 'shared_scripts')) do
        H.loadInto(H.VP, path)
        if path:find('/config%.lua$') then
            H.VP.Config.Compat.database = 'none'
            H.VP.Config.General.banner = false
            if opts.config then opts.config(H.VP.Config) end
        end
    end
    for _, path in ipairs(H.manifest(VP_DIR, 'server_scripts')) do H.loadInto(H.VP, path) end

    for _, fn in ipairs(H.events.onResourceStart or {}) do H.run(fn, 'v-park') end

    local guard = 0
    while not H.VP.Runtime.ready() and guard < 200 do H.step(250); guard = guard + 1 end
    assert(H.VP.Runtime.ready(), 'v-park never became ready')
    H.step(5000)
end
