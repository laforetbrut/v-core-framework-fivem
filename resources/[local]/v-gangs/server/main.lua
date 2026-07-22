-- v-gangs | server
-- Territory, and only territory. Membership, ranks and the treasury are v-factions' —
-- this module exists for what the illegal side does NOT share with a legal faction.
--
-- The capture rule: influence belongs to whoever holds the turf. A rival does not take
-- influence, they wear it down, and the turf only changes hands once it reaches zero.
-- That is what makes a contested turf a fight instead of a race to a number.

local Core
local Turfs = {}          -- world definitions
local State = {}          -- [turfId] = { owner, influence, contested }

local function num(v, d) return tonumber(v) or d or 0 end

-- ── Settings ──────────────────────────────────────────────────
V.Module({
    label = 'Gangs', category = 'people',
    settings = {
        { key = 'capture',     label = 'Territory capture enabled', type = 'bool',   default = true },
        { key = 'tick',        label = 'Capture pass every (s)',    type = 'number', default = Config.Capture.tick, min = 5, max = 300, step = 1 },
        { key = 'gain',        label = 'Influence gained per pass', type = 'number', default = Config.Capture.gainPerTick, min = 0, max = 50, step = 0.5 },
        { key = 'loss',        label = 'Influence worn down per pass', type = 'number', default = Config.Capture.lossPerTick, min = 0, max = 50, step = 0.5 },
        { key = 'perExtra',    label = 'Bonus per extra member',    type = 'number', default = Config.Capture.perExtra, min = 0, max = 5, step = 0.1 },
        { key = 'maxMult',     label = 'Maximum group multiplier',  type = 'number', default = Config.Capture.maxMult, min = 1, max = 10, step = 0.1 },
        { key = 'decay',       label = 'Influence lost per minute unheld', type = 'number', default = Config.Capture.decayPerMin, min = 0, max = 20, step = 0.1 },
        { key = 'minToHold',   label = 'Below this influence the turf is lost', type = 'number', default = Config.Capture.minToHold, min = 0, max = 100, step = 1 },
        { key = 'blips',       label = 'Show turf blips',           type = 'bool',   default = true },
        { key = 'announce',    label = 'Announce a turf changing hands', type = 'bool', default = true },
    },
})

-- Consumers ask for the capability, not the resource: a server that replaces this
-- module keeps every consumer working.
V.Provide('gangs')


-- ── State ─────────────────────────────────────────────────────
local function pushState(src)
    local payload = { turfs = Turfs, state = State,
                      blips = V.SettingBool('blips', true),
                      colors = Config.GangColors, neutral = Config.NeutralColor,
                      blip = Config.Blip }
    TriggerClientEvent('v-gangs:client:state', src or -1, payload)
end

local function loadState()
    State = {}
    for _, r in ipairs(MySQL.query.await('SELECT * FROM gang_turfs') or {}) do
        State[r.turf] = { owner = r.owner, influence = num(r.influence), contested = false }
    end
    for _, tf in ipairs(Turfs) do
        if not State[tf.id] then State[tf.id] = { owner = nil, influence = 0, contested = false } end
    end
end

local function saveTurf(id)
    local st = State[id]
    if not st then return end
    MySQL.query.await([[INSERT INTO gang_turfs (turf, owner, influence) VALUES (?,?,?)
        ON DUPLICATE KEY UPDATE owner=VALUES(owner), influence=VALUES(influence)]],
        { id, st.owner, math.floor(st.influence + 0.5) })
end

local function loadTurfs()
    if GetResourceState('v-world') ~= 'started' then return end
    Turfs = exports['v-world']:GetTurfs() or {}
    loadState()
    pushState()
end

AddEventHandler('v-world:server:changed', function(domain)
    if domain == nil or domain == 'turfs' or domain == 'gangs' then loadTurfs() end
end)

RegisterNetEvent('v-gangs:server:request', function() pushState(source) end)

-- ── Capture ───────────────────────────────────────────────────
local function gangOf(src)
    local p = Core.GetPlayer(src)
    if not p then return nil end
    -- `player.gang` is a TABLE, never a string.
    if type(p.gang) ~= 'table' then return nil end
    local n = p.gang.name
    if not n or n == '' or n == 'none' then return nil end
    return n
end

--- Who is standing in each turf, per gang.
local function presence()
    local byTurf = {}
    for _, sid in ipairs(GetPlayers()) do
        local src = tonumber(sid)
        local gang = src and gangOf(src)
        if gang then
            local ped = GetPlayerPed(src)
            if ped and ped ~= 0 then
                local c = GetEntityCoords(ped)
                for _, tf in ipairs(Turfs) do
                    if tf.enabled ~= false then
                        local d = #(c - vector3(tf.x + 0.0, tf.y + 0.0, tf.z + 0.0))
                        -- Height is ignored beyond a generous slab: a turf is a place on
                        -- the map, and a player on a first floor is still in it.
                        if d <= num(tf.radius, 90.0) then
                            byTurf[tf.id] = byTurf[tf.id] or {}
                            byTurf[tf.id][gang] = (byTurf[tf.id][gang] or 0) + 1
                        end
                    end
                end
            end
        end
    end
    return byTurf
end

local function mult(count)
    local extra = num(V.Setting('perExtra', Config.Capture.perExtra), Config.Capture.perExtra)
    local cap = num(V.Setting('maxMult', Config.Capture.maxMult), Config.Capture.maxMult)
    return math.min(cap, 1.0 + math.max(0, count - 1) * extra)
end

local function announce(turfLabel, gang)
    if not V.SettingBool('announce', true) then return end
    local label = gang
    local def = V.Use('v-factions').Get(gang, 'gang')
    if def and def.label then label = def.label end
    for _, sid in ipairs(GetPlayers()) do
        local src = tonumber(sid)
        if src and gangOf(src) then
            Core.Notify(src, ('%s — %s'):format(turfLabel, label), 'warning')
        end
    end
end

local function step()
    if not V.SettingBool('capture', true) then return end
    local here = presence()
    local tickS = math.max(1, num(V.Setting('tick', Config.Capture.tick), Config.Capture.tick))
    local gain = num(V.Setting('gain', Config.Capture.gainPerTick), Config.Capture.gainPerTick)
    local loss = num(V.Setting('loss', Config.Capture.lossPerTick), Config.Capture.lossPerTick)
    local decay = num(V.Setting('decay', Config.Capture.decayPerMin), Config.Capture.decayPerMin) * (tickS / 60.0)
    local minHold = num(V.Setting('minToHold', Config.Capture.minToHold), Config.Capture.minToHold)

    for _, tf in ipairs(Turfs) do
        if tf.enabled ~= false then
            local st = State[tf.id]
            if st then
                local crowd = here[tf.id] or {}
                local before, prevOwner = st.influence, st.owner

                -- The biggest group present that is NOT the owner is the challenger.
                local challenger, challengerN = nil, 0
                local ownerN = st.owner and (crowd[st.owner] or 0) or 0
                for gang, n in pairs(crowd) do
                    if gang ~= st.owner and n > challengerN then challenger, challengerN = gang, n end
                end
                st.contested = (ownerN > 0 and challengerN > 0)

                if not st.owner then
                    -- Free turf: the biggest group present claims it outright.
                    if challenger then
                        st.owner = challenger
                        st.influence = math.min(100, st.influence + gain * mult(challengerN))
                    else
                        st.influence = math.max(0, st.influence - decay)
                    end
                elseif ownerN > 0 and challengerN == 0 then
                    st.influence = math.min(100, st.influence + gain * mult(ownerN))
                elseif challengerN > 0 then
                    -- Being outnumbered is what actually costs influence; the owner
                    -- standing their ground slows the bleed instead of stopping it.
                    local net = loss * mult(challengerN) - gain * mult(ownerN)
                    st.influence = math.max(0, st.influence - math.max(0, net))
                    if st.influence <= minHold then
                        st.owner = challenger
                        st.influence = math.max(minHold, gain * mult(challengerN))
                    end
                else
                    st.influence = math.max(0, st.influence - decay)
                    if st.influence < minHold then st.owner = nil end
                end

                if st.owner ~= prevOwner then
                    if st.owner then announce(tf.label or tf.id, st.owner) end
                    Core.Log('gangs', ('turf %s: %s -> %s'):format(
                        tf.id, prevOwner or 'nobody', st.owner or 'nobody'))
                end
                if st.owner ~= prevOwner or math.abs(st.influence - before) >= 0.5 then
                    saveTurf(tf.id)
                end
            end
        end
    end
    pushState()
end

CreateThread(function()
    while GetResourceState('oxmysql') ~= 'started' do Wait(100) end
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS `gang_turfs` (
        `turf` VARCHAR(40) NOT NULL,
        `owner` VARCHAR(50) DEFAULT NULL,
        `influence` FLOAT NOT NULL DEFAULT 0,
        `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        PRIMARY KEY (`turf`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])

    while true do
        -- Read the interval every pass: it is admin-tunable, and caching it here would
        -- mean a change only took effect after a restart.
        Wait(math.max(1, num(V.Setting('tick', Config.Capture.tick), Config.Capture.tick)) * 1000)
        local ok, err = pcall(step)
        if not ok then print(('[v-gangs] capture pass failed: %s'):format(err)) end
    end
end)

-- ── Exports ───────────────────────────────────────────────────
exports('GetState', function() return State end)
exports('GetTurfs', function() return Turfs end)

exports('GetOwner', function(turfId)
    local st = State[tostring(turfId or '')]
    return st and st.owner or nil
end)

--- Which turf are these coordinates in, if any? The one thing v-drugs will ask.
exports('TurfAt', function(coords)
    if not coords then return nil end
    for _, tf in ipairs(Turfs) do
        if tf.enabled ~= false then
            if #(coords - vector3(tf.x + 0.0, tf.y + 0.0, tf.z + 0.0)) <= num(tf.radius, 90.0) then
                return tf.id, State[tf.id] and State[tf.id].owner or nil
            end
        end
    end
    return nil
end)

--- Is this player standing in territory their own gang controls? The gate a turf-locked
--- drug sale or a gang stash needs, in one call.
exports('InOwnTurf', function(src)
    local gang = gangOf(src)
    if not gang then return false end
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return false end
    local c = GetEntityCoords(ped)
    for _, tf in ipairs(Turfs) do
        if tf.enabled ~= false and #(c - vector3(tf.x + 0.0, tf.y + 0.0, tf.z + 0.0)) <= num(tf.radius, 90.0) then
            local st = State[tf.id]
            if st and st.owner == gang then return true, tf.id end
        end
    end
    return false
end)

--- Hand a turf over without a capture. Admin-only path: v-world calls this from the
--- Editor, and it is logged like any other ownership change.
exports('SetOwner', function(turfId, owner, byCid)
    local id = tostring(turfId or '')
    local st = State[id]
    if not st then return false end
    if owner == '' then owner = nil end
    st.owner = owner
    st.influence = owner and 100.0 or 0.0
    saveTurf(id)
    pushState()
    Core.Log('gangs', ('turf %s handed to %s'):format(id, owner or 'nobody'), nil, byCid)
    return true
end)

-- ── Boot ──────────────────────────────────────────────────────
V.Ready(function(core)
    Core = core
    local tries = 0
    while GetResourceState('v-world') == 'started' and not exports['v-world']:IsReady() and tries < 100 do
        Wait(100); tries = tries + 1
    end
    if GetResourceState('v-world') == 'started' then
        exports['v-world']:SeedGangs(Config.Gangs)
        exports['v-world']:SeedTurfs(Config.Turfs)
        loadTurfs()
    end
end)
