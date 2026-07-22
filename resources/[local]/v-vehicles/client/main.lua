-- v-vehicles | client
-- Reads and writes the *visual* state of a vehicle entity (mods, colours, damage, fuel)
-- and enforces the key gate as UX. Every decision that matters was already made server-side.
local Core = exports['v-core']:GetCore()

local myKeys = {}     -- plate -> true (mirror of the server's session keys, for the HUD/UX)
local fuelOf = {}     -- plate -> current fuel %, drained locally while we drive

local function strings()
    return Locales[(LocalPlayer.state and LocalPlayer.state.lang) or 'fr'] or Locales.fr or {}
end
local function L(k, ...)
    local s = strings()[k] or k
    if select('#', ...) > 0 then return (s:format(...)) end
    return s
end

local function plateOf(veh)
    if not veh or veh == 0 then return nil end
    local p = GetVehicleNumberPlateText(veh)
    return p and (p:gsub('%s+$', '')) or nil
end

-- ── Property read / write ──────────────────────────────────────
local function getProps(veh)
    if not DoesEntityExist(veh) then return {} end
    local ok, prim = GetVehicleColours(veh)
    local _, pearl, wheelCol = GetVehicleExtraColours(veh)
    local props = {
        color1 = ok, color2 = prim, pearl = pearl, wheelColor = wheelCol,
        wheels = GetVehicleWheelType(veh),
        windowTint = GetVehicleWindowTint(veh),
        plateIndex = GetVehicleNumberPlateTextIndex(veh),
        livery = GetVehicleLivery(veh),
        neon = { GetVehicleNeonLightEnabled(veh, 0), GetVehicleNeonLightEnabled(veh, 1),
                 GetVehicleNeonLightEnabled(veh, 2), GetVehicleNeonLightEnabled(veh, 3) },
        mods = {}, extras = {}, turbo = IsToggleModOn(veh, 18),
        xenon = IsToggleModOn(veh, 22),
    }
    local nr, ng, nb = GetVehicleNeonLightsColour(veh)
    props.neonColor = { nr, ng, nb }
    local tr, tg, tb = GetVehicleTyreSmokeColor(veh)
    props.tyreSmoke = { tr, tg, tb }
    for _, slot in ipairs(Config.ModSlots) do
        local v = GetVehicleMod(veh, slot)
        if v ~= -1 then props.mods[tostring(slot)] = v end
    end
    for i = 0, 20 do
        if DoesExtraExist(veh, i) then props.extras[tostring(i)] = IsVehicleExtraTurnedOn(veh, i) end
    end
    return props
end

local function applyProps(veh, props)
    if not DoesEntityExist(veh) or type(props) ~= 'table' then return end
    SetVehicleModKit(veh, 0)   -- required before any SetVehicleMod call
    if props.color1 then SetVehicleColours(veh, props.color1, props.color2 or props.color1) end
    if props.pearl then SetVehicleExtraColours(veh, props.pearl, props.wheelColor or 0) end
    if props.wheels then SetVehicleWheelType(veh, props.wheels) end
    if props.windowTint then SetVehicleWindowTint(veh, props.windowTint) end
    if props.plateIndex then SetVehicleNumberPlateTextIndex(veh, props.plateIndex) end
    if props.livery and props.livery ~= -1 then SetVehicleLivery(veh, props.livery) end
    for slot, v in pairs(props.mods or {}) do SetVehicleMod(veh, tonumber(slot) or 0, v, false) end
    for i, on in pairs(props.extras or {}) do SetVehicleExtra(veh, tonumber(i) or 0, not on) end
    if props.turbo ~= nil then ToggleVehicleMod(veh, 18, props.turbo and true or false) end
    if props.xenon ~= nil then ToggleVehicleMod(veh, 22, props.xenon and true or false) end
    if type(props.neon) == 'table' then
        for i = 0, 3 do SetVehicleNeonLightEnabled(veh, i, props.neon[i + 1] and true or false) end
    end
    if type(props.neonColor) == 'table' then
        SetVehicleNeonLightsColour(veh, props.neonColor[1] or 255, props.neonColor[2] or 255, props.neonColor[3] or 255)
    end
    if type(props.tyreSmoke) == 'table' then
        SetVehicleTyreSmokeColor(veh, props.tyreSmoke[1] or 255, props.tyreSmoke[2] or 255, props.tyreSmoke[3] or 255)
    end
end

exports('GetProps', function(veh) return getProps(veh) end)
exports('ApplyProps', function(veh, props) applyProps(veh, props) end)
exports('HasKeysLocal', function(plate) return myKeys[plate] == true end)
exports('GetFuel', function(veh)
    local p = plateOf(veh)
    return (p and fuelOf[p]) or 100
end)

-- ── State handed down by the server on spawn ───────────────────
RegisterNetEvent('v-vehicles:client:applyState', function(netid, state)
    local tries = 0
    while not NetworkDoesEntityExistWithNetworkId(netid) and tries < 100 do Wait(20); tries = tries + 1 end
    local veh = NetToVeh(netid)
    if not veh or veh == 0 or not DoesEntityExist(veh) then return end
    applyProps(veh, state.props)
    SetVehicleEngineHealth(veh, (tonumber(state.engine) or 1000) + 0.0)
    SetVehicleBodyHealth(veh, (tonumber(state.body) or 1000) + 0.0)
    if state.plate then
        myKeys[state.plate] = true
        fuelOf[state.plate] = tonumber(state.fuel) or 100
        SetVehicleFuelLevel(veh, (fuelOf[state.plate] / 100.0) * 65.0)
    end
end)

RegisterNetEvent('v-vehicles:client:keys', function(plate, on)
    if type(plate) ~= 'string' then return end
    myKeys[plate] = on and true or nil
end)

-- The server wants this vehicle's condition written down. Only answer for an entity we
-- can actually see — otherwise every client would report a guess.
RegisterNetEvent('v-vehicles:client:reportState', function(plate, netid)
    if not NetworkDoesEntityExistWithNetworkId(netid) then return end
    local veh = NetToVeh(netid)
    if not veh or veh == 0 or not DoesEntityExist(veh) then return end
    if #(GetEntityCoords(PlayerPedId()) - GetEntityCoords(veh)) > 60.0 then return end
    TriggerServerEvent('v-vehicles:server:reportState', plate, {
        props  = getProps(veh),
        fuel   = math.floor(fuelOf[plate] or ((GetVehicleFuelLevel(veh) / 65.0) * 100)),
        engine = math.floor(GetVehicleEngineHealth(veh)),
        body   = math.floor(GetVehicleBodyHealth(veh)),
    })
end)

-- ── Key gate: no keys, no engine ───────────────────────────────
-- This is deliberately a soft gate. The authoritative answer already came from the
-- server (`v-vehicles:hasKeys`); killing the engine client-side is how the player
-- *experiences* it, not how it is enforced.
local checking, lastPlate = false, nil

CreateThread(function()
    if not Config.Keys.lockEngine then return end
    while true do
        local wait = 750
        local ped = PlayerPedId()
        local veh = GetVehiclePedIsIn(ped, false)
        if veh ~= 0 and GetPedInVehicleSeat(veh, -1) == ped then
            local plate = plateOf(veh)
            if plate and plate:sub(1, #Config.PlatePrefix) == Config.PlatePrefix then
                if plate ~= lastPlate and not checking then
                    checking, lastPlate = true, plate
                    Core.TriggerCallback('v-vehicles:hasKeys', function(ok)
                        myKeys[plate] = ok or nil
                        checking = false
                        if not ok then Core.Notify(L('veh.nokeys'), 'error') end
                    end, plate)
                end
                if not myKeys[plate] then
                    wait = 0
                    SetVehicleEngineOn(veh, false, true, true)
                    DisableControlAction(0, 71, true)   -- accelerate
                end
            end
        else
            lastPlate = nil
        end
        Wait(wait)
    end
end)

-- ── Fuel drain ─────────────────────────────────────────────────
CreateThread(function()
    while true do
        Wait(10000)   -- 6 ticks per minute
        local veh = GetVehiclePedIsIn(PlayerPedId(), false)
        if veh ~= 0 and GetIsVehicleEngineRunning(veh) then
            local plate = plateOf(veh)
            if plate and fuelOf[plate] then
                fuelOf[plate] = math.max(0, fuelOf[plate] - (Config.FuelDrain / 6.0))
                SetVehicleFuelLevel(veh, (fuelOf[plate] / 100.0) * 65.0)
                if fuelOf[plate] <= 0 then SetVehicleEngineOn(veh, false, true, true) end
            end
        end
    end
end)
