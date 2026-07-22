-- v-music | server
-- Owns the sources. Never the audio: the server sends a URL, a start timestamp and a
-- position, and every client plays it locally attenuated by its own distance - the same
-- rule `v-3dsound` follows for one-shots.
--
-- **Sync is by timestamp, not by streaming.** Everyone gets the source and an offset, so a
-- player arriving late joins mid-track instead of restarting it for everybody.

local Core
local Sources = {}      -- [id] = { id, kind, owner, x, y, z, netid, url, title, startedAt, volume, range, paused, pausedAt }
local Jukeboxes = {}
local nextId = 1

local function num(v, d) return tonumber(v) or d or 0 end

local function L(src, k)
    local p = Core and Core.GetPlayer(src)
    local lang = (p and p.lang) or 'fr'
    return (Locales[lang] or Locales.fr or {})[k] or k
end

-- ── Settings ──────────────────────────────────────────────────
V.Module({
    label = 'Music', category = 'gameplay',
    settings = {
        { key = 'enabled',   label = 'Music sources enabled',   type = 'bool',   default = true },
        { key = 'allowed',   label = 'Allowed hosts (comma list, blank = any)', type = 'string',
          default = table.concat(Config.AllowedHosts, ','), maxLength = 400,
          hint = 'Blank lets anyone stream anything to everyone in earshot. That is a moderation decision, not a technical one.' },
        { key = 'maxRange',  label = 'Maximum range any source may ask for (m)', type = 'number', default = Config.MaxRange, min = 5, max = 300, step = 5 },
        { key = 'volume',    label = 'Default volume', type = 'number', default = Config.DefaultVolume, min = 0, max = 1, step = 0.05 },
        { key = 'boombox',   label = 'Boomboxes enabled', type = 'bool', default = true },
        { key = 'maxBoombox', label = 'Boomboxes per player', type = 'number', default = Config.Boombox.maxPerPlayer, min = 1, max = 5, step = 1 },
        { key = 'vehicle',   label = 'Car stereo enabled', type = 'bool', default = true },
        { key = 'outsideMult', label = 'Car stereo volume outside the car', type = 'number', default = Config.Vehicle.outsideMult, min = 0, max = 1, step = 0.05 },
        { key = 'jukebox',   label = 'Jukeboxes enabled', type = 'bool', default = true },
        { key = 'logPlays',  label = 'Log what was played and by whom', type = 'bool', default = true },
    },
})

-- ── URL policy ────────────────────────────────────────────────
local function hostOf(url)
    return tostring(url or ''):match('^%a+://([^/:]+)') or ''
end

local function allowedUrl(url)
    url = tostring(url or '')
    if not url:match('^https?://') then return false end
    local raw = tostring(V.Setting('allowed', table.concat(Config.AllowedHosts, ',')))
    if raw:gsub('%s', '') == '' then return true end          -- deliberately open
    local host = hostOf(url):lower()
    for entry in raw:gmatch('[^,]+') do
        -- Lua 5.4 makes a for-loop variable const, so the cleaned value needs its own name.
        local h = entry:gsub('%s', ''):lower()
        if h ~= '' and (host == h or host:sub(-(#h + 1)) == '.' .. h) then return true end
    end
    return false
end

-- ── Sources ───────────────────────────────────────────────────
local function push(src)
    -- The whole set every time: a client that misses one delta would otherwise keep
    -- playing something the world has stopped.
    TriggerClientEvent('v-music:client:sources', src or -1, Sources,
        num(V.Setting('outsideMult', Config.Vehicle.outsideMult), Config.Vehicle.outsideMult))
end

local function findByOwnerKind(cid, kind)
    local n, first = 0, nil
    for _, s in pairs(Sources) do
        if s.owner == cid and s.kind == kind then
            n = n + 1
            first = first or s
        end
    end
    return n, first
end

--- Who may touch this source? The owner, and inside a vehicle whoever holds the keys.
--- Reuse, not reinvention: `v-vehicles` already knows what a key is.
local function mayControl(src, s)
    if not s then return false end
    local p = Core.GetPlayer(src)
    if not p then return false end
    if s.owner == p.citizenid then return true end
    if s.kind == 'vehicle' and s.plate then
        return V.Use('v-vehicles').HasKeys(src, s.plate) == true
    end
    if s.kind == 'jukebox' then
        local j = Jukeboxes[s.id]
        if j and j.job then
            return type(p.job) == 'table' and p.job.name == j.job
        end
        return true      -- an open jukebox is anybody's
    end
    return false
end

local function nearEnough(src, s)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return false end
    local pos
    if s.netid then
        local ent = NetworkGetEntityFromNetworkId(s.netid)
        if ent and ent ~= 0 and DoesEntityExist(ent) then pos = GetEntityCoords(ent) end
    end
    pos = pos or vector3(num(s.x), num(s.y), num(s.z))
    return #(GetEntityCoords(ped) - pos) <= (Config.Distance + 4.0)
end

local function stop(id, byCid)
    local s = Sources[id]
    if not s then return end
    Sources[id] = nil
    push()
    if V.SettingBool('logPlays', true) then
        Core.Log('music', ('%s source %s stopped'):format(s.kind, tostring(id)), nil, byCid)
    end
end

-- ── Callbacks ─────────────────────────────────────────────────
V.Callback('v-music:list', function(src, resolve)
    local p = Core.GetPlayer(src)
    local mine = {}
    for id, s in pairs(Sources) do
        if mayControl(src, s) then mine[#mine + 1] = { id = id, kind = s.kind, title = s.title,
                                                        url = s.url, paused = s.paused, volume = s.volume } end
    end
    resolve({ ok = true, sources = mine, enabled = V.SettingBool('enabled', true),
              cid = p and p.citizenid or nil })
end)

V.Callback('v-music:play', function(src, resolve, data)
    if not V.SettingBool('enabled', true) then resolve({ error = 'off' }) return end
    if type(data) ~= 'table' then resolve(false) return end
    local p = Core.GetPlayer(src)
    if not p then resolve(false) return end

    local url = tostring(data.url or '')
    if not allowedUrl(url) then resolve({ error = 'host' }) return end

    local kind = tostring(data.kind or 'boombox')
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then resolve(false) return end
    local coords = GetEntityCoords(ped)

    local id, s
    if kind == 'vehicle' then
        if not V.SettingBool('vehicle', true) then resolve({ error = 'off' }) return end
        local veh = GetVehiclePedIsIn(ped, false)
        if not veh or veh == 0 then resolve({ error = 'novehicle' }) return end
        local plate = GetVehicleNumberPlateText(veh):gsub('%s+$', '')
        -- Keys, not proximity: a passenger should not be able to hijack the stereo.
        if V.Use('v-vehicles').HasKeys(src, plate) ~= true then resolve({ error = 'nokeys' }) return end
        id = 'veh:' .. plate
        s = Sources[id] or { id = id, kind = 'vehicle', plate = plate }
        s.netid = NetworkGetNetworkIdFromEntity(veh)
        s.range = num(Config.Vehicle.range, 22.0)

    elseif kind == 'jukebox' then
        if not V.SettingBool('jukebox', true) then resolve({ error = 'off' }) return end
        local j = Jukeboxes[tostring(data.id or '')]
        if not j then resolve({ error = 'nosource' }) return end
        if #(coords - vector3(j.x + 0.0, j.y + 0.0, j.z + 0.0)) > (Config.Distance + 4.0) then
            resolve({ error = 'far' }) return
        end
        if j.job and not (type(p.job) == 'table' and p.job.name == j.job) then
            resolve({ error = 'notyours' }) return
        end
        id = 'juke:' .. j.id
        s = Sources[id] or { id = id, kind = 'jukebox' }
        s.x, s.y, s.z = j.x, j.y, j.z
        s.range = num(Config.Jukebox.range, 28.0)

    else
        if not V.SettingBool('boombox', true) then resolve({ error = 'off' }) return end
        local item = tostring(Config.Boombox.item)
        if (tonumber(V.Use('v-inventory').GetItemCount(src, item)) or 0) < 1 then
            resolve({ error = 'noitem' }) return
        end
        local n = findByOwnerKind(p.citizenid, 'boombox')
        local maxB = math.floor(num(V.Setting('maxBoombox', Config.Boombox.maxPerPlayer), 1))
        if n >= maxB then resolve({ error = 'toomany' }) return end
        id = 'box:' .. p.citizenid .. ':' .. nextId
        nextId = nextId + 1
        -- The position is the player's, never the payload's.
        s = { id = id, kind = 'boombox', x = coords.x, y = coords.y, z = coords.z - 0.9,
              range = num(Config.Boombox.range, 35.0) }
    end

    s.owner = s.owner or p.citizenid
    s.url = url
    s.title = tostring(data.title or ''):sub(1, 80)
    s.volume = math.max(0, math.min(1, num(data.volume, V.Setting('volume', Config.DefaultVolume))))
    s.range = math.min(num(V.Setting('maxRange', Config.MaxRange), Config.MaxRange), num(s.range, 25.0))
    -- The clock is the sync: a client joining later computes its own offset from this.
    s.startedAt = os.time()
    s.paused = false

    Sources[id] = s
    push()
    if V.SettingBool('logPlays', true) then
        Core.Log('music', ('%s played %s on a %s'):format(p.citizenid, url, s.kind), nil, p.citizenid)
    end
    resolve({ ok = true, id = id })
end)

V.Callback('v-music:control', function(src, resolve, data)
    if type(data) ~= 'table' then resolve(false) return end
    local s = Sources[tostring(data.id or '')]
    if not s then resolve({ error = 'nosource' }) return end
    if not mayControl(src, s) then resolve({ error = 'notyours' }) return end
    if not nearEnough(src, s) and s.kind ~= 'vehicle' then resolve({ error = 'far' }) return end

    local p = Core.GetPlayer(src)
    local act = tostring(data.action or '')

    if act == 'stop' then
        stop(s.id, p and p.citizenid)
        resolve({ ok = true }) return
    elseif act == 'pause' then
        s.paused = true
        -- Remember where it was, or resuming restarts the track for everybody.
        s.pausedAt = os.time() - num(s.startedAt)
    elseif act == 'resume' then
        s.paused = false
        s.startedAt = os.time() - num(s.pausedAt)
    elseif act == 'volume' then
        s.volume = math.max(0, math.min(1, num(data.volume, s.volume)))
    else
        resolve({ error = 'x' }) return
    end

    push()
    resolve({ ok = true })
end)

-- ── World data ────────────────────────────────────────────────
local function loadJukeboxes()
    Jukeboxes = {}
    if GetResourceState('v-world') ~= 'started' then return end
    for _, j in ipairs(exports['v-world']:GetJukeboxes() or {}) do
        if j.enabled ~= false then Jukeboxes[j.id] = j end
    end
    TriggerClientEvent('v-music:client:jukeboxes', -1, Jukeboxes)
end

AddEventHandler('v-world:server:changed', function(domain)
    if domain == nil or domain == 'jukebox' then loadJukeboxes() end
end)

RegisterNetEvent('v-music:server:request', function()
    push(source)
    TriggerClientEvent('v-music:client:jukeboxes', source, Jukeboxes)
end)

-- A boombox belongs to whoever dropped it; when they leave, so does it. Otherwise a
-- server accumulates music nobody can turn off.
AddEventHandler('playerDropped', function()
    local p = Core.GetPlayer(source)
    if not p then return end
    for id, s in pairs(Sources) do
        if s.kind == 'boombox' and s.owner == p.citizenid then Sources[id] = nil end
    end
    push()
end)

V.Ready(function(core)
    Core = core
    local tries = 0
    while GetResourceState('v-world') == 'started' and not exports['v-world']:IsReady() and tries < 100 do
        Wait(100); tries = tries + 1
    end
    if GetResourceState('v-world') == 'started' then
        exports['v-world']:SeedJukeboxes(Config.Jukeboxes)
        loadJukeboxes()
    end
    V.Use('v-inventory').RegisterUsableItem(Config.Boombox.item, function(src)
        TriggerClientEvent('v-music:client:open', src, 'boombox')
    end)
end)

exports('GetSources', function() return Sources end)
exports('StopSource', function(id) stop(tostring(id or '')) end)
exports('IsAllowed',  function(url) return allowedUrl(url) end)
