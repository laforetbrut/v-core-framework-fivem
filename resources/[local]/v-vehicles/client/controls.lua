-- v-vehicles | client/controls.lua
-- The things a driver does that GTA has no button for: indicators, hazards, an engine you
-- can turn off, getting out without killing it, moving between seats, and locking the car.
--
-- Headlights and high beams are NOT here: GTA already cycles them on `H`, and rebinding a
-- control the player already knows is a worse experience than leaving it alone. What this
-- file does about them is make sure nothing else steals the key while you are driving.

local indicator = { left = false, right = false }
local hazards   = false
local blinkOn   = false
local Locked    = {}          -- [plate] = true, mirrored from the server

local function strings()
    return Locales[(LocalPlayer.state and LocalPlayer.state.lang) or 'fr'] or Locales.fr or {}
end
local function LS(k) return strings()[k] or k end

local function plateOfVeh(veh)
    if not veh or veh == 0 then return nil end
    local p = GetVehicleNumberPlateText(veh)
    return p and p:gsub('%s+$', '') or nil
end

local function myVehicle()
    local ped = PlayerPedId()
    local veh = GetVehiclePedIsIn(ped, false)
    if veh == 0 then return nil end
    return veh, plateOfVeh(veh)
end

--- The vehicle you are pointing at, for locking from outside. Deliberately short-ranged:
--- unlocking a car across a car park is how a key becomes a magic wand.
local function nearestVehicle(range)
    local ped = PlayerPedId()
    local veh = GetVehiclePedIsIn(ped, false)
    if veh ~= 0 then return veh, plateOfVeh(veh) end
    veh = GetClosestVehicle(GetEntityCoords(ped), range or 6.0, 0, 71)
    if not veh or veh == 0 then return nil end
    return veh, plateOfVeh(veh)
end

-- ── Indicators and hazards ─────────────────────────────────────
-- GTA's indicator natives are per-side booleans with no blink of their own, so the blink
-- is ours: one timer for every vehicle rather than one per light.
local function applyLights(veh)
    if not veh or veh == 0 or not DoesEntityExist(veh) then return end
    local l = (hazards or indicator.left) and blinkOn
    local r = (hazards or indicator.right) and blinkOn
    SetVehicleIndicatorLights(veh, 1, l)   -- 1 = left
    SetVehicleIndicatorLights(veh, 0, r)   -- 0 = right
end

CreateThread(function()
    while true do
        if hazards or indicator.left or indicator.right then
            blinkOn = not blinkOn
            applyLights(({ myVehicle() })[1])
            Wait(400)
        else
            Wait(500)
        end
    end
end)

local function setIndicator(side)
    if side == 'left' then
        indicator.left, indicator.right = not indicator.left, false
    elseif side == 'right' then
        indicator.right, indicator.left = not indicator.right, false
    end
    if not (indicator.left or indicator.right or hazards) then
        local veh = myVehicle()
        if veh then SetVehicleIndicatorLights(veh, 0, false); SetVehicleIndicatorLights(veh, 1, false) end
    end
end

RegisterCommand('vveh_left',  function() if myVehicle() then setIndicator('left') end end, false)
RegisterCommand('vveh_right', function() if myVehicle() then setIndicator('right') end end, false)
RegisterCommand('vveh_haz', function()
    if not myVehicle() then return end
    hazards = not hazards
    indicator.left, indicator.right = false, false
    if not hazards then
        local veh = myVehicle()
        if veh then SetVehicleIndicatorLights(veh, 0, false); SetVehicleIndicatorLights(veh, 1, false) end
    end
end, false)

RegisterKeyMapping('vveh_left',  'Vehicle: left indicator',  'keyboard', Config.Controls.left)
RegisterKeyMapping('vveh_right', 'Vehicle: right indicator', 'keyboard', Config.Controls.right)
RegisterKeyMapping('vveh_haz',   'Vehicle: hazards',         'keyboard', Config.Controls.hazards)

-- ── Engine ─────────────────────────────────────────────────────
-- The server owns the answer: with `lockEngine` on, no keys means no engine, and that is
-- not a decision a client gets to make about a car it does not own.
RegisterCommand('vveh_engine', function()
    local veh, plate = myVehicle()
    if not veh or not plate then return end
    if GetPedInVehicleSeat(veh, -1) ~= PlayerPedId() then
        V.Notify(LS('veh.notdriver'), 'error') return
    end
    local running = GetIsVehicleEngineRunning(veh)
    V.Request('v-vehicles:engine', function(ok)
        if ok ~= true then V.Notify(LS('veh.nokeys'), 'error') return end
        SetVehicleEngineOn(veh, not running, false, true)
        V.Notify(LS(running and 'veh.engine_off' or 'veh.engine_on'), 'info')
    end, { plate = plate, on = not running })
end, false)
RegisterKeyMapping('vveh_engine', 'Vehicle: engine on/off', 'keyboard', Config.Controls.engine)

-- Getting out without killing it. GTA cuts the engine on exit; a driver who left it
-- running expects to find it running, so the script puts it back.
CreateThread(function()
    local lastVeh, wasRunning = nil, false
    while true do
        Wait(250)
        local ped = PlayerPedId()
        local veh = GetVehiclePedIsIn(ped, false)
        if veh ~= 0 then
            lastVeh = veh
            wasRunning = GetIsVehicleEngineRunning(veh)
        elseif lastVeh and DoesEntityExist(lastVeh) then
            if wasRunning and V.SettingBool('leaveRunning', true)
               and not GetIsVehicleEngineRunning(lastVeh) then
                SetVehicleEngineOn(lastVeh, true, true, true)
            end
            lastVeh, wasRunning = nil, false
        end
    end
end)

-- ── Seats ──────────────────────────────────────────────────────
-- Cycles to the next free seat rather than opening a menu: the choice is almost always
-- "somewhere else in this car", and a menu for that is a menu too many.
RegisterCommand('vveh_seat', function()
    local veh = myVehicle()
    if not veh then return end
    local ped = PlayerPedId()
    local seats = GetVehicleModelNumberOfSeats(GetEntityModel(veh))
    local mine = -2
    for i = -1, seats - 2 do
        if GetPedInVehicleSeat(veh, i) == ped then mine = i break end
    end
    for step = 1, seats do
        local s = mine + step
        if s > seats - 2 then s = s - (seats + 1) end
        if s >= -1 and IsVehicleSeatFree(veh, s) then
            -- A locked car you are already inside stays yours to move around in; the lock
            -- is about getting in, not about sitting still.
            TaskWarpPedIntoVehicle(ped, veh, s)
            return
        end
    end
    V.Notify(LS('veh.noseat'), 'error')
end, false)
RegisterKeyMapping('vveh_seat', 'Vehicle: move to the next free seat', 'keyboard', Config.Controls.seat)

-- ── Locks ──────────────────────────────────────────────────────
RegisterNetEvent('v-vehicles:client:locks', function(list)
    Locked = list or {}
end)

--- Applied continuously to nearby vehicles: the lock lives on the server, and whichever
--- client happens to own the entity has to be told to honour it.
CreateThread(function()
    while true do
        Wait(1500)
        if next(Locked) then
            local me = GetEntityCoords(PlayerPedId())
            local veh = GetClosestVehicle(me, 30.0, 0, 71)
            if veh and veh ~= 0 and DoesEntityExist(veh) then
                local plate = plateOfVeh(veh)
                if plate and Locked[plate] ~= nil then
                    SetVehicleDoorsLocked(veh, Locked[plate] and 2 or 1)
                end
            end
        end
    end
end)

RegisterCommand('vveh_lock', function()
    local veh, plate = nearestVehicle(Config.Controls.lockRange)
    if not veh or not plate then V.Notify(LS('veh.novehicle'), 'error') return end
    V.Request('v-vehicles:toggleLock', function(res)
        if not res or res.error then
            V.Notify(LS('veh.err_' .. ((res and res.error) or 'x')), 'error') return
        end
        SetVehicleDoorsLocked(veh, res.locked and 2 or 1)
        -- The chirp is what tells you it worked from ten metres away.
        PlayVehicleDoorCloseSound(veh, 1)
        V.Notify(LS(res.locked and 'veh.locked' or 'veh.unlocked'), 'success')
    end, { plate = plate })
end, false)
RegisterKeyMapping('vveh_lock', 'Vehicle: lock / unlock', 'keyboard', Config.Controls.lock)

-- ── Lockpicking ────────────────────────────────────────────────
-- The illegal counterpart. Everything that decides anything is server-side; this file
-- plays the animation and waits.
local picking = false

local function lockpick()
    if picking then return end
    local veh, plate = nearestVehicle(3.5)
    if not veh or not plate then V.Notify(LS('veh.novehicle'), 'error') return end
    if not Locked[plate] then V.Notify(LS('veh.err_notlocked'), 'error') return end

    picking = true
    local ped = PlayerPedId()
    RequestAnimDict('veh@break_in@0h@p_m_one@')
    local t = 0
    while not HasAnimDictLoaded('veh@break_in@0h@p_m_one@') and t < 80 do Wait(10); t = t + 1 end
    if HasAnimDictLoaded('veh@break_in@0h@p_m_one@') then
        TaskPlayAnim(ped, 'veh@break_in@0h@p_m_one@', 'low_force_entry_ds', 4.0, -1, -1, 16, 0, false, false, false)
    end

    V.Request('v-vehicles:lockpick', function(res)
        ClearPedTasks(ped)
        picking = false
        if not res or res.error then
            V.Notify(LS('veh.err_' .. ((res and res.error) or 'x')), 'error') return
        end
        if res.ok then
            SetVehicleDoorsLocked(veh, 1)
            V.Notify(LS('veh.picked'), 'success')
        else
            V.Notify(LS(res.broke and 'veh.pick_broke' or 'veh.pick_failed'), 'error')
        end
    end, { plate = plate })
end

RegisterCommand('vveh_pick', lockpick, false)
RegisterKeyMapping('vveh_pick', 'Vehicle: lockpick', 'keyboard', Config.Controls.lockpick)

exports('IsLocked',    function(plate) return Locked[tostring(plate or '')] == true end)
exports('GetIndicator', function() return { left = indicator.left, right = indicator.right, hazards = hazards } end)

V.Ready(function()
    Wait(2000)
    TriggerServerEvent('v-vehicles:server:requestLocks')
end)
