
-- Consumers ask for the capability, not the resource: a server that replaces this
-- module keeps every consumer working.
V.Provide('status')
-- v-status | server
-- Owns hunger / thirst / stress / bleeding / illness. Health & armor stay
-- native and are read client-side by the HUD.
local Core = exports['v-core']:GetCore()

local Status = {}   -- [source] = { hunger, thirst, stress, bleed, sick }
local Dead   = {}   -- [source] = true between a real death (baseevents) and its respawn

local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end

local function default()
    return {
        hunger = Config.Defaults.hunger,
        thirst = Config.Defaults.thirst,
        stress = Config.Defaults.stress,
        bleed  = Config.Defaults.bleed,
        sick   = Config.Defaults.sick,
    }
end

local function sync(src)
    if Status[src] then TriggerClientEvent('v-status:client:update', src, Status[src]) end
end

local function persist(src)
    local player = Core.GetPlayer(src)
    if player then player.SetMetadata('status', Status[src]) end
end

-- Initialise status from saved metadata when a player loads.
AddEventHandler('v-core:server:onPlayerLoaded', function(src, player)
    local saved = player.GetMetadata('status')
    Status[src] = (type(saved) == 'table' and saved.hunger) and saved or default()
    sync(src)
end)

AddEventHandler('playerDropped', function()
    Status[source] = nil
    Dead[source] = nil
end)

-- Server-authoritative death signal (from the baseevents resource, not a raw client
-- event), so onRespawn can only cleanse ONCE per real death.
AddEventHandler('baseevents:onPlayerDied',   function() Dead[source] = true end)
AddEventHandler('baseevents:onPlayerKilled', function() Dead[source] = true end)

-- ── Mutators (called by items, jobs, admin, ...) ───────────────
local function setNeed(src, key, value)
    if not Status[src] then return end
    Status[src][key] = clamp(value, 0, 100)
    persist(src); sync(src)
end

exports('Get',    function(src) return Status[src] end)
exports('Set',    function(src, key, value) setNeed(src, key, value) end)
exports('Add',    function(src, key, delta)
    if Status[src] then setNeed(src, key, (Status[src][key] or 0) + delta) end
end)

exports('SetBleed', function(src, level)
    if not Status[src] then return end
    Status[src].bleed = clamp(level, 0, 4)
    persist(src); sync(src)
end)

exports('SetSick', function(src, level)
    if not Status[src] then return end
    Status[src].sick = clamp(level, 0, 3)
    persist(src); sync(src)
end)

-- Full heal / cleanse (used by EMS / revive later).
exports('Heal', function(src)
    if not Status[src] then return end
    Status[src].bleed = 0
    Status[src].sick  = 0
    persist(src); sync(src)
    TriggerClientEvent('v-status:client:heal', src)
end)

-- ── Injury from taking damage (client-reported) ────────────────
RegisterNetEvent('v-status:server:addBleed', function(amount)
    local src = source
    if not Status[src] then return end
    Status[src].bleed = clamp((Status[src].bleed or 0) + (amount or 1), 0, 4)
    persist(src); sync(src)
    Core.Log('injury', ('%s bleeding -> level %d'):format(src, Status[src].bleed))
end)

RegisterNetEvent('v-status:server:onRespawn', function()
    local src = source
    if not Status[src] or not Dead[src] then return end   -- only after a real death
    Dead[src] = nil
    Status[src].bleed  = 0
    Status[src].hunger = math.max(Status[src].hunger, 50)
    Status[src].thirst = math.max(Status[src].thirst, 50)
    persist(src); sync(src)
end)

-- ── Needs drain tick ───────────────────────────────────────────
CreateThread(function()
    while true do
        Wait(Config.NeedsTick)
        for src, s in pairs(Status) do
            s.hunger = clamp(s.hunger - Config.Drain.hunger, 0, 100)
            s.thirst = clamp(s.thirst - Config.Drain.thirst, 0, 100)
            if s.hunger <= 0 or s.thirst <= 0 then
                TriggerClientEvent('v-status:client:damage', src, Config.StarveDamage, Config.NeedsFloorHealth)
            end
            persist(src); sync(src)
        end
    end
end)

-- ── Bleed tick ─────────────────────────────────────────────────
CreateThread(function()
    while true do
        Wait(Config.BleedTick)
        for src, s in pairs(Status) do
            if s.bleed and s.bleed > 0 then
                TriggerClientEvent('v-status:client:damage', src, Config.BleedDamage[s.bleed] or 2, 0)
                TriggerClientEvent('v-status:client:bleedfx', src, s.bleed)
            end
        end
    end
end)

-- ── Illness tick ───────────────────────────────────────────────
CreateThread(function()
    while true do
        Wait(Config.SickTick)
        for src, s in pairs(Status) do
            if s.sick and s.sick > 0 then
                TriggerClientEvent('v-status:client:damage', src, Config.SickDamage[s.sick] or 1, Config.NeedsFloorHealth)
            end
        end
    end
end)

-- ── Admin test command (permission-gated) ──────────────────────
-- /status <hunger|thirst|stress|bleed|sick> <value>  (self)
RegisterCommand('status', function(source, args)
    if source == 0 or not Core.HasPermission(source, 'admin') then return end
    local key, value = args[1], tonumber(args[2])
    if not Status[source] or not key or not value then return end
    if key == 'bleed' then exports['v-status']:SetBleed(source, value)
    elseif key == 'sick' then exports['v-status']:SetSick(source, value)
    else setNeed(source, key, value) end
end, false)

-- ══════════════════════════════════════════════════════════════════
--  Admin-tunable settings (v-core module registry)
-- ══════════════════════════════════════════════════════════════════
-- Declared to v-core, which stores the values and serves them to the admin panel.
-- Applied back onto Config so the existing code paths see an operator's change without
-- a restart. See DEVELOPERS.md.
local function declareSettings()
    Core.RegisterModule('v-status', {
        label = 'Survival needs', category = 'gameplay',
        settings = {

            { key = 'hungerDrain', label = 'Hunger drain per tick',  type = 'number', default = Config.Drain.hunger, min = 0, max = 25 },
            { key = 'thirstDrain', label = 'Thirst drain per tick',  type = 'number', default = Config.Drain.thirst, min = 0, max = 25 },
            { key = 'needsTick',   label = 'Needs tick (seconds)',   type = 'number', default = Config.NeedsTick / 1000, min = 5, max = 600, step = 1 },
            { key = 'starveDamage',label = 'Damage at 0 need',       type = 'number', default = Config.StarveDamage, min = 0, max = 50, step = 1 },
            { key = 'floorHealth', label = 'Needs never kill below', type = 'number', default = Config.NeedsFloorHealth, min = 101, max = 200, step = 1 },
            { key = 'bleedTick',   label = 'Bleed tick (seconds)',   type = 'number', default = Config.BleedTick / 1000, min = 5, max = 300, step = 1 },
            { key = 'sickTick',    label = 'Illness tick (seconds)', type = 'number', default = Config.SickTick / 1000, min = 5, max = 600, step = 1 },
            { key = 'stressBlur',  label = 'Stress blur from (%)',   type = 'number', default = Config.StressBlurFrom, min = 0, max = 100, step = 1 },
            { key = 'stressShake', label = 'Stress shake from (%)',  type = 'number', default = Config.StressShakeFrom, min = 0, max = 100, step = 1 },
        },
    })
end

local function S(key, fallback) return Core.GetSetting('v-status', key, fallback) end

local function applySettings()

    Config.Drain.hunger      = S('hungerDrain', Config.Drain.hunger)
    Config.Drain.thirst      = S('thirstDrain', Config.Drain.thirst)
    Config.NeedsTick         = math.floor(S('needsTick', Config.NeedsTick / 1000) * 1000)
    Config.StarveDamage      = S('starveDamage', Config.StarveDamage)
    Config.NeedsFloorHealth  = S('floorHealth', Config.NeedsFloorHealth)
    Config.BleedTick         = math.floor(S('bleedTick', Config.BleedTick / 1000) * 1000)
    Config.SickTick          = math.floor(S('sickTick', Config.SickTick / 1000) * 1000)
    Config.StressBlurFrom    = S('stressBlur', Config.StressBlurFrom)
    Config.StressShakeFrom   = S('stressShake', Config.StressShakeFrom)
    TriggerClientEvent('v-status:client:tunables', -1, {
        stressBlur = Config.StressBlurFrom, stressShake = Config.StressShakeFrom,
    })
end

AddEventHandler('v-core:server:settingChanged', function(mod)
    if mod == 'v-status' then applySettings() end
end)

V.Ready(function()
    declareSettings()
    applySettings()
end)
