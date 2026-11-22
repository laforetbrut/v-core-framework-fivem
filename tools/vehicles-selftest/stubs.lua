-- Stubs of the FiveM server runtime, oxmysql and v-core, enough to load
-- v-vehicles/server/main.lua outside the game and drive it from a test.
-- Author: vyrriox.

H = { exports = {}, events = {}, net = {}, callbacks = {}, client = {}, fired = {}, entities = {},
      nextEnt = 100, nextNet = 5000, now = 0, threads = {}, players = {}, sql = {} }

-- ── scheduler (virtual time) ──────────────────────────────────
function Wait(ms) coroutine.yield(ms or 0) end
function CreateThread(fn)
    H.threads[#H.threads + 1] = { co = coroutine.create(fn), at = H.now }
end
Citizen = { CreateThread = CreateThread, Wait = Wait }
function H.step(ms)
    local stop = H.now + (ms or 0)
    repeat
        local progressed = false
        for _, t in ipairs(H.threads) do
            if coroutine.status(t.co) == 'suspended' and t.at <= H.now then
                local ok, wait = coroutine.resume(t.co)
                if not ok then error('thread failed: ' .. tostring(wait)) end
                t.at = H.now + (tonumber(wait) or 0)
                progressed = true
            end
        end
        if not progressed then
            local nxt
            for _, t in ipairs(H.threads) do
                if coroutine.status(t.co) == 'suspended' and (not nxt or t.at < nxt) then nxt = t.at end
            end
            if not nxt or nxt > stop then break end
            H.now = nxt
        end
    until false
    H.now = math.max(H.now, stop)
end
--- Run fn as a thread to completion (it may Wait), return its results.
function H.run(fn, ...)
    local args, res = table.pack(...), nil
    CreateThread(function() res = table.pack(fn(table.unpack(args, 1, args.n))) end)
    local guard = 0
    while not res and guard < 10000 do H.step(50); guard = guard + 1 end
    assert(res, 'H.run: thread never finished')
    return table.unpack(res, 1, res.n)
end

-- ── vectors ───────────────────────────────────────────────────
local vmt = {}
vmt.__index = vmt
vmt.__sub = function(a, b) return vector3(a.x - b.x, a.y - b.y, a.z - b.z) end
vmt.__len = function(a) return math.sqrt(a.x * a.x + a.y * a.y + a.z * a.z) end
function vector3(x, y, z) return setmetatable({ x = x, y = y, z = z }, vmt) end

-- ── json (identity through a registry) ────────────────────────
local jreg, jn = {}, 0
json = {
    encode = function(t) jn = jn + 1; local k = 'J#' .. jn; jreg[k] = t; return k end,
    decode = function(s) return jreg[s] end,
}

-- ── events / exports ──────────────────────────────────────────
function RegisterNetEvent(name, fn) if fn then H.net[name] = fn end end
function AddEventHandler(name, fn)
    H.events[name] = H.events[name] or {}
    table.insert(H.events[name], fn)
end
function TriggerEvent(name, ...)
    H.fired[#H.fired + 1] = { name = name, args = table.pack(...) }
    for _, fn in ipairs(H.events[name] or {}) do fn(...) end
end
function TriggerClientEvent(name, target, ...)
    if target == nil then error('TriggerClientEvent with a nil target: ' .. name) end
    H.client[#H.client + 1] = { name = name, target = target, args = table.pack(...) }
end
function H.firedNamed(name)
    local out = {}
    for _, f in ipairs(H.fired) do if f.name == name then out[#out + 1] = f end end
    return out
end
function GetCurrentResourceName() return 'v-vehicles' end
H.resState = {}
function GetResourceState(n) return H.resState[n] or 'started' end
function GetPlayers() return {} end

local Core = {
    GetPlayer = function(src) return H.players[src] end,
    RegisterCallback = function(name, fn) H.callbacks[name] = fn end,
    GetSetting = function(_, _, def) return def end,
    RegisterModule = function() end,
    Log = function() end,
    Notify = function() end,
}
exports = setmetatable({}, {
    __call = function(_, name, fn) H.exports[name] = fn end,
    __index = function(_, res)
        if res == 'v-core' then return { GetCore = function() return Core end } end
        return setmetatable({}, { __index = function(_, m)
            return function(_, ...) return H.exports[m](...) end
        end })
    end,
})
V = { Provide = function() return true end }
L = function(k) return k end
LP = function(_, k) return k end

-- ── entities ──────────────────────────────────────────────────
function GetHashKey(s)
    local h = 0
    for i = 1, #s do h = (h * 31 + s:byte(i)) & 0x7FFFFFFF end
    return h
end
local function newEntity(model, x, y, z, h, how)
    H.nextEnt, H.nextNet = H.nextEnt + 1, H.nextNet + 1
    local e = { id = H.nextEnt, net = H.nextNet, model = type(model) == 'string' and GetHashKey(model) or model,
                pos = vector3(x, y, z), heading = h, plate = 'RANDOM12', how = how, alive = true }
    H.entities[e.id] = e
    return e.id
end
function CreateVehicle(model, x, y, z, h) return newEntity(model, x, y, z, h, 'rpc') end
function CreateVehicleServerSetter(model, kind, x, y, z, h)
    assert(type(model) == 'number', 'setter wants a hash')
    local id = newEntity(model, x, y, z, h, 'setter')
    H.entities[id].kind = kind
    return id
end
function DoesEntityExist(e) return H.entities[e] ~= nil and H.entities[e].alive end
function DeleteEntity(e) if H.entities[e] then H.entities[e].alive = false end end
function SetVehicleNumberPlateText(e, p) H.entities[e].plate = p end
function GetVehicleNumberPlateText(e) return (H.entities[e].plate .. '        '):sub(1, 8) end
function NetworkGetNetworkIdFromEntity(e) return H.entities[e].net end
function NetworkGetEntityFromNetworkId(n)
    for id, e in pairs(H.entities) do if e.net == n and e.alive then return id end end
    return 0
end
function GetAllVehicles()
    local out = {}
    for id, e in pairs(H.entities) do if e.alive then out[#out + 1] = id end end
    table.sort(out)
    return out
end
function GetEntityCoords(e) return H.entities[e].pos end
function GetEntityHeading(e) return H.entities[e].heading end
function GetEntityModel(e) return H.entities[e].model end
function GetVehicleType(e) return H.entities[e].kind or 'automobile' end
function SetEntityRotation(e, x, y, z) H.entities[e].rot = { x, y, z } end
function SetEntityRoutingBucket(e, b) H.entities[e].bucket = b end
function SetEntityOrphanMode(e, m) H.entities[e].orphan = m end
function SetEntityDistanceCullingRadius(e, r) H.entities[e].culling = r end
function GetPlayerPed() return 0 end

-- ── oxmysql over an in-memory character_vehicles ──────────────
H.cols = { id = true, citizenid = true, plate = true, model = true, props = true, garage = true,
           state = true, fuel = true, engine = true, body = true, created_at = true,
           parts = true, mileage = true, last_service = true }
H.rows, H.nextId = {}, 1

local function trim(s) return (s:gsub('^%s+', ''):gsub('%s+$', '')) end
local function col(c)
    c = trim(c):gsub('`', '')
    if not H.cols[c] then error("Unknown column '" .. c .. "'") end
    return c
end
local function splitTop(s, sep)
    local out, depth, cur, i = {}, 0, '', 1
    while i <= #s do
        local ch = s:sub(i, i)
        if ch == '(' then depth = depth + 1 elseif ch == ')' then depth = depth - 1 end
        if depth == 0 and s:sub(i, i + #sep - 1) == sep then
            out[#out + 1] = cur; cur = ''; i = i + #sep
        else
            cur = cur .. ch; i = i + 1
        end
    end
    out[#out + 1] = cur
    return out
end
local function matches(row, where, params, pi)
    for _, cond in ipairs(splitTop(where, ' AND ')) do
        local c, op = cond:match('^%s*([%w_`]+)%s*([<>=]+)%s*%?%s*$')
        assert(c, 'unsupported WHERE: ' .. cond)
        c = col(c)
        local v = params[pi]; pi = pi + 1
        if op == '=' then if row[c] ~= v then return false, pi end
        elseif op == '<>' then if row[c] == v then return false, pi end
        else error('op ' .. op) end
    end
    return true, pi
end
local function select(sql, params)
    sql = trim(sql:gsub('%s+', ' '))
    sql = sql:gsub(' ORDER BY [%w_]+$', '')
    local what, where = sql:match('^SELECT (.-) FROM character_vehicles WHERE (.*)$')
    assert(what, 'unsupported SELECT: ' .. sql)
    local out = {}
    local ids = {}
    for id in pairs(H.rows) do ids[#ids + 1] = id end
    table.sort(ids)
    for _, id in ipairs(ids) do
        local row = H.rows[id]
        if matches(row, where, params, 1) then
            local r = {}
            for _, item in ipairs(splitTop(what, ', ')) do
                item = trim(item)
                local fn, arg, alias = item:match('^([%w_]+)%(([%w_]+)%) AS ([%w_]+)$')
                if item == '*' then for k, v in pairs(row) do r[k] = v end
                elseif item == '1' then r['1'] = 1
                elseif fn == 'UNIX_TIMESTAMP' then r[alias] = row[col(arg)]
                else local c = col(item); r[c] = row[c] end
            end
            out[#out + 1] = r
        end
    end
    return out
end
local function run(sql, params)
    params = params or {}
    H.sql[#H.sql + 1] = sql
    local flat = trim(sql:gsub('%s+', ' '))
    if flat:find('information_schema', 1, true) then
        return { { ['1'] = H.cols[params[2]] and 1 or nil } }, 'select'
    end
    local alter = flat:match('^ALTER TABLE `character_vehicles` ADD COLUMN `([%w_]+)`')
    if alter then H.cols[alter] = true; return {}, 'ddl' end
    if flat:match('^SELECT') then return select(flat, params), 'select' end
    local set, where = flat:match('^UPDATE character_vehicles SET (.-) WHERE (.*)$')
    if set then
        local items, pi = splitTop(set, ', '), 1
        local plan = {}
        for _, it in ipairs(items) do
            local c, rhs = it:match('^%s*([%w_`]+)%s*=%s*(.-)%s*$')
            c = col(c)
            if rhs == '?' then plan[#plan + 1] = { c, 'p', params[pi] }; pi = pi + 1
            elseif rhs == 'NULL' then plan[#plan + 1] = { c, 'v', nil }
            elseif rhs == 'CURRENT_TIMESTAMP' then plan[#plan + 1] = { c, 'v', H.now }
            elseif rhs:match('^COALESCE%(%?, ([%w_]+)%)$') then plan[#plan + 1] = { c, 'c', params[pi] }; pi = pi + 1
            else error('unsupported SET: ' .. it) end
        end
        local n = 0
        for _, row in pairs(H.rows) do
            if matches(row, where, params, pi) then
                for _, p in ipairs(plan) do
                    if p[2] == 'c' then if p[3] ~= nil then row[p[1]] = p[3] end
                    else row[p[1]] = p[3] end
                end
                n = n + 1
            end
        end
        return n, 'update'
    end
    local icols = flat:match('^INSERT INTO character_vehicles %((.-)%)')
    if icols then
        local row = { id = H.nextId }; H.nextId = H.nextId + 1
        local vals = {}
        for v in flat:match('VALUES %((.-)%)$'):gmatch('[^,]+') do vals[#vals + 1] = trim(v) end
        local pi = 1
        for i, c in ipairs(splitTop(icols, ',')) do
            c = col(c)
            if vals[i] == '?' then row[c] = params[pi]; pi = pi + 1 else row[c] = tonumber(vals[i]) end
        end
        H.rows[row.id] = row
        return row.id, 'insert'
    end
    error('unsupported SQL: ' .. flat)
end
H.runSql = run

MySQL = {
    scalar = { await = function(s, p) local r = run(s, p); local f = r[1]; if not f then return nil end
        for _, v in pairs(f) do return v end end },
    single = { await = function(s, p) return run(s, p)[1] end },
    query  = { await = function(s, p) return (run(s, p)) end },
    update = { await = function(s, p) return (run(s, p)) end },
    insert = { await = function(s, p) return (run(s, p)) end },
}
setmetatable(MySQL.update, { __call = function(_, s, p) run(s, p) end })
setmetatable(MySQL.query, { __call = function(_, s, p) run(s, p) end })

function H.addRow(t)
    local row = { id = H.nextId, citizenid = 'CID1', plate = 'VR00001', model = 'sultan', props = json.encode({}),
                  garage = 'legion', state = 1, fuel = 100, engine = 1000, body = 1000 }
    for k, v in pairs(t or {}) do row[k] = v end
    H.nextId = H.nextId + 1
    H.rows[row.id] = row
    return row
end
function H.row(plate) for _, r in pairs(H.rows) do if r.plate == plate then return r end end end
