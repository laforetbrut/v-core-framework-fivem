-- v-3dsound | server
-- Broadcasts the INTENT to play a sound. Never audio data: the bank is on every client
-- already, so the wire carries a name, a position and a range.
--
-- The rule that matters: **anything a player can cause goes through here**, and the
-- position is re-derived from the player rather than taken from a payload. A sound a
-- client triggers and broadcasts itself is a griefing tool.

local Core
local Rate = {}       -- [source] = { n, at }

local function num(v, d) return tonumber(v) or d or 0 end

-- ── Settings ──────────────────────────────────────────────────
V.Module({
    label = '3D sound', category = 'other',
    settings = {
            { key = 'nativeOnly', label = 'Native sounds only (no custom files)', type = 'bool', default = false },
        { key = 'enabled',  label = 'Positional sound enabled', type = 'bool',   default = true },
        { key = 'maxRange', label = 'Maximum range any caller may ask for (m)', type = 'number', default = Config.MaxRange, min = 5, max = 500, step = 5 },
        { key = 'volume',   label = 'Master volume for custom sounds', type = 'number', default = Config.Volume, min = 0, max = 1, step = 0.05 },
        { key = 'perMin',   label = 'Sounds per source per minute', type = 'number', default = Config.MaxPerMin, min = 1, max = 600, step = 1 },
        { key = 'custom',   label = 'Allow custom sound files', type = 'bool', default = true },
    },
})

-- Consumers ask for the capability, not the resource: a server that replaces this
-- module keeps every consumer working.
V.Provide('sound')


local function def(name) return Config.Bank[tostring(name or '')] end

--- A budget per calling source. A looping script is the realistic way this floods, not a
--- cheater: either way the fix is the same.
local function overRate(key)
    local now = GetGameTimer()
    local r = Rate[key]
    if not r or now - r.at > 60000 then Rate[key] = { n = 1, at = now } return false end
    r.n = r.n + 1
    return r.n > math.max(1, math.floor(num(V.Setting('perMin', Config.MaxPerMin), Config.MaxPerMin)))
end

--- Who is close enough to hear it? Sending to everyone and letting each client decide
--- would put every sound on every wire, which is exactly what a proximity system is for.
local function listeners(coords, range)
    local out = {}
    for _, sid in ipairs(GetPlayers()) do
        local src = tonumber(sid)
        local ped = src and GetPlayerPed(src)
        if ped and ped ~= 0 and #(GetEntityCoords(ped) - coords) <= range then
            out[#out + 1] = src
        end
    end
    return out
end

local function play(name, coords, opts)
    if not V.SettingBool('enabled', true) then return false end
    local d = def(name)
    if not d then return false end
    if d.file and not V.SettingBool('custom', true) then return false end
    -- A server that wants zero downloads refuses the file bank outright.
    if d.file and V.SettingBool('nativeOnly', false) then return false end

    opts = opts or {}
    local cap = num(V.Setting('maxRange', Config.MaxRange), Config.MaxRange)
    local range = math.min(cap, math.max(1.0, num(opts.range, num(d.range, 15.0))))
    local volume = math.max(0.0, math.min(1.0, num(opts.volume, num(d.volume, 1.0))))

    local payload = {
        name = tostring(name), set = d.set, sound = d.sound, file = d.file,
        x = coords.x, y = coords.y, z = coords.z,
        range = range, volume = volume,
        master = num(V.Setting('volume', Config.Volume), Config.Volume),
        netid = opts.netid,
    }
    for _, src in ipairs(listeners(coords, range)) do
        TriggerClientEvent('v-3dsound:client:play', src, payload)
    end
    return true
end

-- ── Exports ───────────────────────────────────────────────────
--- Play at a world position. For scripted world events (an alarm, a machine).
exports('Play', function(name, coords, opts)
    if type(coords) ~= 'vector3' then
        if type(coords) == 'table' and coords.x then coords = vector3(coords.x + 0.0, coords.y + 0.0, coords.z + 0.0)
        else return false end
    end
    if overRate('world:' .. tostring(name)) then return false end
    return play(name, coords, opts)
end)

--- Play AT a player, with the position taken from their ped. This is the one every
--- gameplay module should use: the caller cannot name a position it does not occupy.
exports('PlayFromPlayer', function(src, name, opts)
    src = tonumber(src)
    if not src then return false end
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return false end
    if overRate('src:' .. src) then return false end
    return play(name, GetEntityCoords(ped), opts)
end)

--- Play on an entity, so the sound follows a moving car or ped.
exports('PlayOnEntity', function(entity, name, opts)
    entity = tonumber(entity)
    if not entity or entity == 0 or not DoesEntityExist(entity) then return false end
    if overRate('ent:' .. entity) then return false end
    opts = opts or {}
    opts.netid = NetworkGetNetworkIdFromEntity(entity)
    return play(name, GetEntityCoords(entity), opts)
end)

--- Play for one person only. Not positional; the private counterpart of the above.
exports('PlayFor', function(src, name, opts)
    src = tonumber(src)
    local d = def(name)
    if not src or not d then return false end
    if not V.SettingBool('enabled', true) then return false end
    TriggerClientEvent('v-3dsound:client:play', src, {
        name = tostring(name), set = d.set, sound = d.sound, file = d.file,
        range = 0, volume = math.max(0.0, math.min(1.0, num((opts or {}).volume, num(d.volume, 1.0)))),
        master = num(V.Setting('volume', Config.Volume), Config.Volume), personal = true,
    })
    return true
end)

exports('GetBank', function() return Config.Bank end)
exports('Has',     function(name) return def(name) ~= nil end)

AddEventHandler('playerDropped', function() Rate['src:' .. source] = nil end)

V.Ready(function(core) Core = core end)
