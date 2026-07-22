-- v-anticheat | server
-- Sanity checks on the things a client should never be able to decide for itself.
--
-- The single most important design choice here is that **the default action is to log**.
-- An anticheat that kicks legitimate players is worse than no anticheat: it costs a server
-- its population, and it costs the operator their trust in the tool. Every detector ships
-- noisy-but-harmless so an operator can watch their own logs before arming anything.
--
-- The second is `Expect`. Six modules in this framework legitimately teleport a player -
-- spawn, garages, the dealership showroom, clothing rooms, jail, admin tools. A teleport
-- detector that does not know about them flags the framework itself.

local Core
local Pos = {}        -- [source] = { x, y, z, at }
local Grace = {}      -- [source] = { [kind] = expiryMs }
local Rate = {}       -- [source] = { [kind] = { count, windowStart } }
local Flags = {}      -- [source] = count this session

local function num(v, d) return tonumber(v) or d or 0 end

-- ── Settings ──────────────────────────────────────────────────
V.Module({
    label = 'Anticheat', category = 'other',
    settings = {
        { key = 'action',     label = 'What a flag does', type = 'select', default = Config.DefaultAction,
          options = { { value = 'log', label = 'Log only' }, { value = 'warn', label = 'Log + tell staff' },
                      { value = 'kick', label = 'Kick' }, { value = 'ban', label = 'Ban' } },
          hint = 'Start on log. Watch your own logs for a week before arming this.' },
        { key = 'exemptTier', label = 'Staff at or above this tier are never flagged', type = 'select',
          default = Config.ExemptTier,
          options = { { value = 'mod', label = 'Moderator' }, { value = 'admin', label = 'Admin' },
                      { value = 'superadmin', label = 'Superadmin' } } },
        { key = 'teleport',   label = 'Detect impossible movement', type = 'bool', default = Config.Detectors.teleport.enabled },
        { key = 'maxSpeed',   label = 'Maximum speed (m/s)', type = 'number', default = Config.Detectors.teleport.maxSpeed, min = 20, max = 1000, step = 5 },
        { key = 'health',     label = 'Detect impossible health', type = 'bool', default = Config.Detectors.health.enabled },
        { key = 'explosion',  label = 'Detect explosion abuse', type = 'bool', default = Config.Detectors.explosion.enabled },
        { key = 'expPerMin',  label = 'Explosions allowed per minute', type = 'number', default = Config.Detectors.explosion.perMinute, min = 1, max = 120, step = 1 },
        { key = 'entity',     label = 'Detect client entity spawning', type = 'bool', default = Config.Detectors.entity.enabled },
        { key = 'entPerMin',  label = 'Entities allowed per minute', type = 'number', default = Config.Detectors.entity.perMinute, min = 1, max = 200, step = 1 },
        { key = 'money',      label = 'Detect impossible money changes', type = 'bool', default = Config.Detectors.money.enabled },
        { key = 'maxDelta',   label = 'Largest legitimate money change ($)', type = 'number', default = Config.Detectors.money.maxDelta, min = 1000, max = 100000000, step = 1000 },
        { key = 'weapon',     label = 'Detect impossible weapon damage', type = 'bool', default = Config.Detectors.weapon.enabled },
        { key = 'maxDist',    label = 'Maximum damage distance (m)', type = 'number', default = Config.Detectors.weapon.maxDistance, min = 50, max = 2000, step = 10 },
        { key = 'grace',      label = 'Grace window after a declared action (s)', type = 'number', default = Config.GraceSeconds, min = 1, max = 60, step = 1 },
    },
})

-- ── Exemptions ────────────────────────────────────────────────
local function exempt(src)
    if not Core then return true end
    local tier = tostring(V.Setting('exemptTier', Config.ExemptTier))
    local ok = Core.HasPermission(src, tier)
    return ok == true
end

--- Declare that a module is about to do something a detector would otherwise flag.
--- Deliberately short-lived: a grace window is a hole, and a wide one is a wide hole.
local function expect(src, kind, seconds)
    src = tonumber(src)
    if not src then return false end
    kind = tostring(kind or '')
    Grace[src] = Grace[src] or {}
    local window = math.max(1, math.floor(num(seconds, V.Setting('grace', Config.GraceSeconds))))
    Grace[src][kind] = GetGameTimer() + window * 1000
    return true
end

local function graced(src, kind)
    local g = Grace[src]
    if not g or not g[kind] then return false end
    if GetGameTimer() > g[kind] then g[kind] = nil return false end
    return true
end

-- ── Flagging ──────────────────────────────────────────────────
local function flag(src, kind, detail)
    if exempt(src) then return end

    local p = Core.GetPlayer(src)
    local cid = p and p.citizenid or nil
    Flags[src] = (Flags[src] or 0) + 1

    -- Everything lands in the existing audit log, so there is no second place to look and
    -- the admin panel's Logs tab already shows it.
    Core.Log('anticheat', ('%s: %s'):format(kind, tostring(detail or '')),
        { source = src, name = GetPlayerName(src) or '?', flags = Flags[src] }, cid)

    local action = tostring(V.Setting('action', Config.DefaultAction))
    if action == 'log' then return end

    if action == 'warn' or action == 'kick' or action == 'ban' then
        for _, sid in ipairs(GetPlayers()) do
            local s = tonumber(sid)
            if s and Core.HasPermission(s, 'mod') then
                Core.Notify(s, ('[AC] %s - %s'):format(GetPlayerName(src) or '?', kind), 'warning')
            end
        end
    end

    if action == 'kick' then
        DropPlayer(src, ('Anticheat: %s'):format(kind))
    elseif action == 'ban' then
        -- Banning is delegated: v-core owns permissions and identity, and a second ban
        -- list is a second thing to get out of sync.
        if p then
            Core.Log('anticheat', ('ban requested for %s (%s)'):format(cid, kind), nil, cid)
        end
        DropPlayer(src, ('Anticheat: %s'):format(kind))
    end
end

--- Count an event against a per-minute budget. Returns true when the budget is blown.
local function overRate(src, kind, perMinute)
    Rate[src] = Rate[src] or {}
    local r = Rate[src][kind]
    local now = GetGameTimer()
    if not r or now - r.at > 60000 then
        Rate[src][kind] = { n = 1, at = now }
        return false
    end
    r.n = r.n + 1
    return r.n > math.max(1, math.floor(perMinute))
end

-- ── Impossible movement ───────────────────────────────────────
CreateThread(function()
    while true do
        local interval = math.max(1, math.floor(Config.Detectors.teleport.sampleSeconds))
        Wait(interval * 1000)
        if V.SettingBool('teleport', Config.Detectors.teleport.enabled) and Core then
            local maxSpeed = num(V.Setting('maxSpeed', Config.Detectors.teleport.maxSpeed), Config.Detectors.teleport.maxSpeed)
            for _, sid in ipairs(GetPlayers()) do
                local src = tonumber(sid)
                local ped = src and GetPlayerPed(src)
                if ped and ped ~= 0 then
                    local c = GetEntityCoords(ped)
                    local last = Pos[src]
                    local now = GetGameTimer()
                    if last and not graced(src, 'teleport') then
                        local dt = (now - last.at) / 1000.0
                        if dt > 0.5 then
                            local speed = #(c - vector3(last.x, last.y, last.z)) / dt
                            -- A player still loading, or one the engine has not streamed
                            -- in, reads as a huge jump. Ignore anything at the origin.
                            if speed > maxSpeed and #(c) > 1.0 and #(vector3(last.x, last.y, last.z)) > 1.0 then
                                flag(src, 'teleport', ('%.0f m/s'):format(speed))
                            end
                        end
                    end
                    Pos[src] = { x = c.x, y = c.y, z = c.z, at = now }
                end
            end
        end
    end
end)

-- ── Impossible health ─────────────────────────────────────────
CreateThread(function()
    while true do
        Wait(7000)
        if V.SettingBool('health', Config.Detectors.health.enabled) and Core then
            for _, sid in ipairs(GetPlayers()) do
                local src = tonumber(sid)
                local ped = src and GetPlayerPed(src)
                if ped and ped ~= 0 and not graced(src, 'health') then
                    local hp = GetEntityHealth(ped)
                    if hp > Config.Detectors.health.maxHealth then
                        flag(src, 'health', ('hp %d'):format(hp))
                    end
                    local armour = GetPedArmour(ped)
                    if armour > Config.Detectors.health.maxArmour then
                        flag(src, 'armour', ('armour %d'):format(armour))
                    end
                end
            end
        end
    end
end)

-- ── Explosions ────────────────────────────────────────────────
AddEventHandler('explosionEvent', function(sender, ev)
    local src = tonumber(sender)
    if not src or not Core then return end
    if not V.SettingBool('explosion', Config.Detectors.explosion.enabled) then return end
    if exempt(src) or graced(src, 'explosion') then return end

    local kind = math.floor(num(ev and ev.explosionType, -1))
    if Config.Detectors.explosion.blocked[kind] then
        CancelEvent()
        flag(src, 'explosion', ('blocked type %d'):format(kind))
        return
    end
    if overRate(src, 'explosion', num(V.Setting('expPerMin', Config.Detectors.explosion.perMinute), Config.Detectors.explosion.perMinute)) then
        CancelEvent()
        flag(src, 'explosion', ('rate, type %d'):format(kind))
    end
end)

-- ── Client-side entity creation ───────────────────────────────
-- Every legitimate spawn in this framework goes through the server (v-vehicles owns the
-- only vehicle spawn path), so a client creating entities at speed is already unusual.
AddEventHandler('entityCreating', function(entity)
    if not Core then return end
    if not V.SettingBool('entity', Config.Detectors.entity.enabled) then return end
    local owner = NetworkGetEntityOwner(entity)
    local src = owner and owner > 0 and owner or nil
    if not src or exempt(src) or graced(src, 'entity') then return end

    if overRate(src, 'entity', num(V.Setting('entPerMin', Config.Detectors.entity.perMinute), Config.Detectors.entity.perMinute)) then
        CancelEvent()
        flag(src, 'entity', 'spawn rate')
    end
end)

-- ── Weapon damage ─────────────────────────────────────────────
AddEventHandler('weaponDamageEvent', function(sender, ev)
    local src = tonumber(sender)
    if not src or not Core then return end
    if not V.SettingBool('weapon', Config.Detectors.weapon.enabled) then return end
    if exempt(src) or graced(src, 'weapon') then return end

    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return end
    local hit = ev and ev.hitGlobalIds and ev.hitGlobalIds[1]
    if not hit then return end
    local victim = NetworkGetEntityFromNetworkId(hit)
    if not victim or victim == 0 or not DoesEntityExist(victim) then return end

    local dist = #(GetEntityCoords(ped) - GetEntityCoords(victim))
    local maxDist = num(V.Setting('maxDist', Config.Detectors.weapon.maxDistance), Config.Detectors.weapon.maxDistance)
    if dist > maxDist then
        CancelEvent()
        flag(src, 'weapon', ('damage at %.0f m'):format(dist))
    end
end)

-- ── Money ─────────────────────────────────────────────────────
-- v-core already fires this; the anticheat only listens. A change with no reason attached
-- did not come from a module in this framework, which is the interesting part.
AddEventHandler('v-core:server:onMoneyChange', function(src, account, balance, reason)
    if not Core then return end
    if not V.SettingBool('money', Config.Detectors.money.enabled) then return end
    if exempt(src) then return end

    local maxDelta = num(V.Setting('maxDelta', Config.Detectors.money.maxDelta), Config.Detectors.money.maxDelta)
    if math.abs(num(balance)) > maxDelta * 20 then
        flag(src, 'money', ('%s balance %d'):format(tostring(account), math.floor(num(balance))))
    end
    if reason == nil or tostring(reason) == '' then
        flag(src, 'money', ('%s changed with no reason'):format(tostring(account)))
    end
end)

-- ── Housekeeping ──────────────────────────────────────────────
AddEventHandler('playerDropped', function()
    Pos[source], Grace[source], Rate[source], Flags[source] = nil, nil, nil, nil
end)

-- A freshly connected player has no previous position, and the first sample after a spawn
-- always looks like a teleport.
AddEventHandler('v-core:server:onPlayerLoaded', function(src)
    Pos[src] = nil
    expect(src, 'teleport', 15)
end)

V.Ready(function(core) Core = core end)

-- ── Exports ───────────────────────────────────────────────────
--- Declare an action a detector would otherwise flag. Six modules in this framework
--- legitimately teleport a player; without this the anticheat flags the framework.
exports('Expect',  function(src, kind, seconds) return expect(src, kind, seconds) end)
exports('Flag',    function(src, kind, detail) flag(src, kind, detail) end)
exports('IsExempt', function(src) return exempt(src) end)
exports('GetFlags', function(src) return Flags[tonumber(src) or 0] or 0 end)
