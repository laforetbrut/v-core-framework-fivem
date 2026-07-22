-- v-core | client/world.lua
-- World policy: what the *game* is allowed to do on its own.
--
-- GTA's built-in police are the single biggest thing standing between a server and
-- immersive roleplay. An NPC cruiser that spawns out of nowhere, a wanted star that paints
-- the minimap red, a dispatch helicopter overhead - none of it is played by anyone, and
-- all of it overrides whatever the actual police module was doing. **So it is off by
-- default**, and an operator turns back on only the pieces they want.
--
-- Everything here is a live setting: flip it in the admin panel and it applies at once, on
-- every client, with no restart.

local applied = {}
local override = {}   -- key -> value, wins over the setting until cleared

local function S(key, fallback)
    if override[key] ~= nil then return override[key] end
    if not VCore or not VCore.GetSetting then return fallback end
    local v = VCore.GetSetting('v-core', key, fallback)
    if v == nil then return fallback end
    return v
end

local function bool(key, fallback)
    local v = S(key, fallback)
    return v == true or v == 1 or v == '1' or v == 'true'
end

-- Dispatch service ids, grouped by who they belong to. Splitting them is the point: a
-- server can keep NPC ambulances and fire trucks while having no NPC police at all.
local POLICE_DISPATCH = { 1, 2, 4, 6, 7, 8, 9, 10, 11, 12, 13, 14 }
local EMERGENCY_DISPATCH = { 3, 5 }

local function applyWorld()
    local pid = PlayerId()

    local npcPolice = bool('npcPolice', false)
    local emergency = bool('npcEmergency', false)
    local randomCops = bool('randomCops', false)
    local randomEvents = bool('randomEvents', false)

    -- Police response. `SetPoliceIgnorePlayer` alone is not enough: dispatch still runs
    -- and still draws blips, so the services have to be switched off too.
    SetPoliceIgnorePlayer(pid, not npcPolice)
    SetDispatchCopsForPlayer(pid, npcPolice)
    for _, id in ipairs(POLICE_DISPATCH) do EnableDispatchService(id, npcPolice) end
    for _, id in ipairs(EMERGENCY_DISPATCH) do EnableDispatchService(id, emergency) end

    -- The wanted ceiling is what stops a star appearing at all. Clearing a level after the
    -- fact still flashes the minimap, which is exactly the immersion break we are removing.
    local maxWanted = math.floor(tonumber(S('maxWanted', 0)) or 0)
    if not npcPolice then maxWanted = 0 end
    SetMaxWantedLevel(math.max(0, math.min(5, maxWanted)))

    -- Ambient traffic and pedestrians the game invents on its own.
    SetCreateRandomCops(randomCops)
    SetCreateRandomCopsNotOnScenarios(randomCops)
    SetCreateRandomCopsOnScenarios(randomCops)
    SetRandomEventFlag(randomEvents)

    SetRandomTrains(bool('randomTrains', true))
    SetRandomBoats(bool('randomBoats', true))
    SetGarbageTrucks(bool('garbageTrucks', false))

    applied = { npcPolice = npcPolice, maxWanted = maxWanted }
end

-- Applied once on join and again whenever an admin changes a setting, rather than every
-- frame: these are engine state, not per-frame draw calls.
AddEventHandler('v-core:client:onPlayerLoaded', function()
    Wait(1500)
    applyWorld()
end)

AddEventHandler('v-core:client:onSettingChanged', function(mod)
    if mod == 'v-core' then applyWorld() end
end)

CreateThread(function()
    -- The engine resets some of these on a respawn or a session change, and a script that
    -- reapplies once at boot quietly stops working an hour in.
    while true do
        Wait(30000)
        applyWorld()
    end
end)

-- The wanted level is the one piece that needs watching rather than setting: a mission,
-- a scripted event or another resource can hand out a star even with dispatch disabled.
CreateThread(function()
    while true do
        Wait(700)
        if applied.npcPolice == false then
            local pid = PlayerId()
            if GetPlayerWantedLevel(pid) > 0 then
                SetPlayerWantedLevel(pid, 0, false)
                SetPlayerWantedLevelNow(pid, false)
            end
        end
    end
end)

--- Let another module suspend the policy briefly - a scripted chase, a heist, a training
--- scenario. An override WINS over the setting until it is cleared with nil, so a module
--- that forgets to clean up does not permanently silence the admin panel by accident: the
--- operator can see the difference between the two in GetWorldPolicy.
exports('SetWorldPolicy', function(key, value)
    if type(key) ~= 'string' then return false end
    override[key] = value
    applyWorld()
    return true
end)

exports('ClearWorldPolicy', function(key)
    if key == nil then override = {} else override[key] = nil end
    applyWorld()
    return true
end)

exports('GetWorldPolicy', function()
    return { applied = applied, overrides = override }
end)
