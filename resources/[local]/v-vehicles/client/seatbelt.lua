-- v-vehicles | client/seatbelt.lua
-- Seatbelt + windscreen ejection. Every serious RP server has this: without it a
-- 200 km/h head-on is survivable and nobody has any reason to drive carefully.
--
-- The ejection is driven by DECELERATION, not by collision events: reading the speed
-- delta between two frames catches every impact (car, wall, water, ped) with one rule
-- and no native event to miss.

local buckled   = false
local wasInVeh  = false
local lastSpeed = 0.0
local lastTick  = 0

local function core()
    if GetResourceState('v-core') ~= 'started' then return nil end
    local ok, c = pcall(function() return exports['v-core']:GetCore() end)
    return ok and c or nil
end

local function setting(key, fallback)
    local c = core()
    if not c or not c.GetSetting then return fallback end
    local ok, v = pcall(c.GetSetting, 'v-vehicles', key, fallback)
    if ok and v ~= nil then return v end
    return fallback
end

local function L(k)
    local lang = (LocalPlayer.state and LocalPlayer.state.lang) or 'fr'
    return (Locales[lang] or Locales.fr or {})[k] or k
end

local function notify(k, kind)
    local c = core()
    if c and c.Notify then pcall(c.Notify, L(k), kind or 'info') end
end

-- A seated ped only flies through the windscreen when the engine allows it, so the
-- belt is enforced by clearing that flag rather than by catching the ejection later.
local function applyFlag(ped)
    SetPedConfigFlag(ped, 32, not buckled)   -- CPED_CONFIG_FLAG_CanFlyThruWindscreen
end

local function seatedInCar(ped)
    local veh = GetVehiclePedIsIn(ped, false)
    if veh == 0 then return nil end
    local class = GetVehicleClass(veh)
    -- Bikes, boats, planes and helicopters have no belt to speak of.
    if class == 8 or class == 13 or class == 14 or class == 15 or class == 16 then return nil end
    return veh
end

local function toggle()
    local ped = PlayerPedId()
    if not seatedInCar(ped) then return end
    if setting('seatbelt', true) == false then return end
    buckled = not buckled
    applyFlag(ped)
    PlaySoundFrontend(-1, buckled and 'Faster_Click' or 'Menu_Back',
                      'RESPAWN_ONLINE_SOUNDSET', true)
    notify(buckled and 'veh.belt_on' or 'veh.belt_off', buckled and 'success' or 'warning')
end

RegisterCommand('vveh_belt', toggle, false)
RegisterKeyMapping('vveh_belt', 'Toggle seatbelt', 'keyboard', 'B')

-- Other modules ask us, rather than us reaching into the HUD: the belt belongs to the
-- vehicle module, and a server without v-hud still gets the behaviour.
exports('IsBuckled', function() return buckled end)

CreateThread(function()
    while true do
        local ped = PlayerPedId()
        local veh = seatedInCar(ped)

        if not veh then
            if wasInVeh then
                wasInVeh, buckled, lastSpeed = false, false, 0.0
                applyFlag(ped)
            end
            Wait(400)
        else
            if not wasInVeh then
                -- A fresh vehicle always starts unbuckled: carrying the belt over from
                -- the last car is how players end up "protected" without ever buckling.
                wasInVeh, buckled = true, false
                lastSpeed, lastTick = GetEntitySpeed(veh), GetGameTimer()
                applyFlag(ped)
            end

            local speed = GetEntitySpeed(veh)
            local now = GetGameTimer()
            local dt = math.max(1, now - lastTick)
            lastTick = now

            if buckled then
                -- Holding the flag off every tick: scripts and the engine both reset it.
                applyFlag(ped)
            else
                -- Deceleration normalised to a fixed 100 ms window, so the admin setting
                -- means the same thing whatever the tick rate — and so this loop does not
                -- have to run every frame to stay accurate. A crash dumps far more than
                -- the threshold in 100 ms; hard braking dumps roughly 4 km/h.
                local drop = (lastSpeed - speed) * 3.6 * (100.0 / dt)
                local trigger = tonumber(setting('ejectDrop', 55)) or 55
                local minSpeed = (tonumber(setting('ejectMinSpeed', 60)) or 60) / 3.6

                if lastSpeed > minSpeed and drop > trigger
                   and GetPedInVehicleSeat(veh, -1) == ped then
                    -- Out through the windscreen, then ragdoll: SetPedToRagdoll alone
                    -- leaves the ped inside the car.
                    local c = GetEntityCoords(ped)
                    local fwd = GetEntityForwardVector(veh)
                    SetEntityCoords(ped, c.x + fwd.x * 2.2, c.y + fwd.y * 2.2, c.z - 0.4,
                                    true, false, false, false)
                    SetPedToRagdoll(ped, 4000, 4000, 0, false, false, false)
                    ApplyForceToEntity(ped, 1, fwd.x * 14.0, fwd.y * 14.0, 3.0,
                                       0.0, 0.0, 0.0, 0, true, true, true, false, true)
                    -- The crash itself is what hurts; this is the cost of no belt.
                    local dmg = math.floor(tonumber(setting('ejectDamage', 22)) or 22)
                    SetEntityHealth(ped, math.max(1, GetEntityHealth(ped) - dmg))
                    notify('veh.belt_ejected', 'error')
                end
            end

            lastSpeed = speed
            Wait(50)
        end
    end
end)
