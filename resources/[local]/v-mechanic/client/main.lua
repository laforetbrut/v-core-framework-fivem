-- v-mechanic | client
-- Watches how the car is actually driven, turns that into per-part wear, and makes the
-- car FEEL its condition through the handling natives. The server clamps everything we
-- report; what we own here is the observation and the driving experience.
local Core = exports['v-core']:GetCore()

local Shops = Config.Shops
local blips = {}
local isOpen, curShop, curPlate = false, nil, nil

local tracked = {}     -- plate -> { parts, mileage, pending = {key=delta}, lastPos, lastSave }
local warned = {}      -- plate -> { part = true }  (so a warning fires once per part)

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

local function isEV(veh)
    if GetResourceState('v-fuel') ~= 'started' then return false end
    return exports['v-fuel']:GetFuelType(veh) == 'electric'
end

local function partSet(ev) return ev and Config.PartsEV or Config.Parts end

-- ── Applying condition to the car ──────────────────────────────
-- Above Config.DegradeBelow nothing happens. Below it the penalty ramps linearly to the
-- part's floor at 0, so a car degrades gradually rather than falling off a cliff.
local function factor(condition, kind)
    local pen = Config.Penalty[kind]
    if not pen then return 1.0 end
    if condition >= Config.DegradeBelow then return 1.0 end
    local t = math.max(0.0, condition / Config.DegradeBelow)
    return pen.floor + (1.0 - pen.floor) * t
end

--- Worst condition among the parts feeding one system — a car is only as good as its
--- weakest link, which is also how a driver experiences it.
local function worst(parts, ev, kind)
    local v = 100
    for _, def in ipairs(partSet(ev)) do
        if def.affects == kind then v = math.min(v, parts[def.key] or 100) end
    end
    return v
end

local function applyCondition(veh, parts, ev)
    if not veh or veh == 0 or not DoesEntityExist(veh) then return end
    local power = factor(worst(parts, ev, 'power'), 'power')
    local brake = factor(worst(parts, ev, 'brakes'), 'brakes')
    local grip  = factor(worst(parts, ev, 'handling'), 'handling')

    -- These multipliers are relative to stock and must be re-applied: the engine resets
    -- them when a vehicle streams back in.
    SetVehicleEnginePowerMultiplier(veh, (power - 1.0) * 100.0)
    SetVehicleEngineTorqueMultiplier(veh, power)
    SetVehicleBrakeForceMultiplier(veh, brake)
    SetVehicleGripMultiplier(veh, grip)

    -- Cooling: a dead radiator/oil filter bleeds engine health while running.
    local cool = worst(parts, ev, 'cooling')
    if cool < Config.WarnBelow and GetIsVehicleEngineRunning(veh) then
        SetVehicleEngineHealth(veh, math.max(150.0, GetVehicleEngineHealth(veh) - 0.6))
    end

    -- Electrics: a flat battery/alternator makes the lights and the starter unreliable.
    local elec = worst(parts, ev, 'electrics')
    if elec < 20 then
        SetVehicleLights(veh, 1)
        if math.random() < 0.04 then SetVehicleEngineOn(veh, false, true, true) end
    end
end

-- ── Wear observation ───────────────────────────────────────────
local function ensure(plate)
    if not tracked[plate] then
        tracked[plate] = { parts = nil, mileage = 0, pending = {}, lastPos = nil, lastSave = GetGameTimer() }
    end
    return tracked[plate]
end

local function addWear(st, key, amount)
    if amount <= 0 then return end
    st.pending[key] = (st.pending[key] or 0) + amount
end

--- Distance-driven wear plus the abuse multipliers, spread over the parts by their
--- individual `wear` factor.
local function accrue(veh, plate, km, hardBrake, redline, offroad)
    local st = ensure(plate)
    local ev = isEV(veh)
    local base = (km / 100.0) * Config.WearPer100km

    -- Neglect: past the service interval everything wears faster.
    local sinceService = st.mileage - (st.service or 0)
    local neglect = (sinceService > Config.Odometer.service) and Config.Odometer.neglect or 1.0

    for _, def in ipairs(partSet(ev)) do
        local mult = 1.0
        if redline   and (def.affects == 'power')    then mult = mult * Config.AbuseMult.redline end
        if hardBrake and (def.affects == 'brakes')   then mult = mult * Config.AbuseMult.hardBrake end
        if offroad   and (def.affects == 'handling') then mult = mult * Config.AbuseMult.offroad end
        addWear(st, def.key, base * (def.wear or 1.0) * mult * neglect)
    end
end

--- A collision damages the systems that took the hit, scaled by how hard it was.
local function crashWear(veh, plate, delta)
    local st = ensure(plate)
    local ev = isEV(veh)
    local sev = math.min(1.0, delta / 300.0)   -- 300 body-health points = a total write-off
    if sev <= 0.01 then return end
    for _, def in ipairs(partSet(ev)) do
        local share = (def.affects == 'body' and 3.0)
            or (def.affects == 'handling' and 1.6)
            or (def.affects == 'cooling' and 1.2)
            or 0.6
        addWear(st, def.key, sev * 14.0 * share * (def.wear or 1.0))
    end
end

-- ── The driving tick ───────────────────────────────────────────
CreateThread(function()
    local lastBody, lastSpeed = nil, 0.0
    while true do
        Wait(Config.TickMs)
        local ped = PlayerPedId()
        local veh = GetVehiclePedIsIn(ped, false)
        if veh ~= 0 and GetPedInVehicleSeat(veh, -1) == ped then
            local plate = plateOf(veh)
            if plate and tracked[plate] and tracked[plate].parts then
                local st = tracked[plate]
                local pos = GetEntityCoords(veh)
                local speed = GetEntitySpeed(veh)

                -- distance since the last tick, in km
                local km = 0.0
                if st.lastPos then km = #(pos - st.lastPos) / 1000.0 end
                st.lastPos = pos
                -- a teleport (garage spawn, admin) is not mileage
                if km > 0.6 then km = 0.0 end
                st.mileage = st.mileage + km

                local top = math.max(1.0, GetVehicleEstimatedMaxSpeed(veh))
                local redline = (speed / top) > 0.88
                local hardBrake = (lastSpeed - speed) > 6.0 and speed < lastSpeed
                local offroad = not IsPointOnRoad(pos.x, pos.y, pos.z, veh)
                lastSpeed = speed

                accrue(veh, plate, km, hardBrake, redline, offroad)

                -- collision damage, read from the body health delta
                local body = GetVehicleBodyHealth(veh)
                if lastBody and body < lastBody - 2.0 then crashWear(veh, plate, lastBody - body) end
                lastBody = body

                -- apply what the condition costs, and warn once per failing part
                local ev = isEV(veh)
                applyCondition(veh, st.parts, ev)
                warned[plate] = warned[plate] or {}
                for _, def in ipairs(partSet(ev)) do
                    local c = st.parts[def.key] or 100
                    if c < Config.WarnBelow and not warned[plate][def.key] then
                        warned[plate][def.key] = true
                        Core.Notify(L('mech.warn', L(def.i18n)), 'warning')
                    elseif c >= Config.WarnBelow then
                        warned[plate][def.key] = nil
                    end
                end

                -- ship the accrued wear to the server on the save interval
                if GetGameTimer() - st.lastSave > Config.SaveInterval * 1000 then
                    st.lastSave = GetGameTimer()
                    local deltas = {}
                    for k, v in pairs(st.pending) do
                        if v > 0.01 then
                            deltas[k] = v
                            st.parts[k] = math.max(0, (st.parts[k] or 100) - v)
                        end
                    end
                    st.pending = {}
                    if next(deltas) then
                        TriggerServerEvent('v-mechanic:server:reportWear', plate, deltas, st.mileage)
                    end
                end
            else
                lastBody, lastSpeed = nil, 0.0
            end
        else
            lastBody, lastSpeed = nil, 0.0
        end
    end
end)

-- The server hands us a plate's condition when it spawns; keep it in sync on repairs.
RegisterNetEvent('v-mechanic:client:partsChanged', function(plate, parts)
    if type(plate) ~= 'string' or type(parts) ~= 'table' then return end
    local st = ensure(plate)
    st.parts = parts
    warned[plate] = nil
end)

RegisterNetEvent('v-mechanic:client:state', function(plate, parts, mileage, service)
    if type(plate) ~= 'string' then return end
    local st = ensure(plate)
    st.parts = (type(parts) == 'table') and parts or {}
    st.mileage = tonumber(mileage) or 0
    st.service = tonumber(service) or 0
end)

-- Admin changed a tunable: the client owns the wear observation, so it needs the numbers.
RegisterNetEvent('v-mechanic:client:tunables', function(t)
    if type(t) ~= 'table' then return end
    Config.WearPer100km = tonumber(t.wearPer100km) or Config.WearPer100km
    Config.DegradeBelow = tonumber(t.degradeBelow) or Config.DegradeBelow
    Config.WarnBelow    = tonumber(t.warnBelow) or Config.WarnBelow
    Config.Odometer.service = tonumber(t.service) or Config.Odometer.service
end)

exports('GetLocalParts', function(plate) return tracked[plate] and tracked[plate].parts or nil end)
exports('GetMileage', function(plate) return tracked[plate] and tracked[plate].mileage or 0 end)

-- ── Shops: blips, marker, prompt ───────────────────────────────
local function clearBlips()
    for _, b in ipairs(blips) do if DoesBlipExist(b) then RemoveBlip(b) end end
    blips = {}
end

local function buildBlips()
    clearBlips()
    for _, sh in ipairs(Shops) do
        if sh.blip ~= 0 then
            local b = AddBlipForCoord(sh.x + 0.0, sh.y + 0.0, sh.z + 0.0)
            SetBlipSprite(b, Config.Blip.sprite); SetBlipColour(b, Config.Blip.color)
            SetBlipScale(b, Config.Blip.scale); SetBlipAsShortRange(b, true)
            BeginTextCommandSetBlipName('STRING')
            AddTextComponentSubstringPlayerName(sh.label or L('mech.blip'))
            EndTextCommandSetBlipName(b)
            blips[#blips + 1] = b
        end
    end
end

RegisterNetEvent('v-mechanic:client:shops', function(list)
    if type(list) ~= 'table' then return end
    Shops = list
    buildBlips()
end)

CreateThread(function()
    Wait(3000)
    TriggerServerEvent('v-mechanic:server:request')
    buildBlips()
end)

local function openDiag(shop, plate)
    if isOpen then return end
    Core.TriggerCallback('v-mechanic:diagnose', function(data)
        if not data or data.error then
            Core.Notify(L('mech.err_' .. ((data and data.error) or 'x')), 'error'); return
        end
        isOpen, curShop, curPlate = true, shop, plate
        SetNuiFocus(true, true)   -- focus is per-resource: only the page owner may take it
        exports['v-core']:MenuOpened()
        SendNUIMessage({ action = 'open', data = data, strings = strings() })
    end, { plate = plate, shop = shop })
end

local function close()
    if not isOpen then return end
    isOpen, curShop, curPlate = false, nil, nil
    SetNuiFocus(false, false)
    exports['v-core']:MenuClosed()
    SendNUIMessage({ action = 'close' })
end

local function refresh()
    if not curPlate then return end
    Core.TriggerCallback('v-mechanic:diagnose', function(data)
        if data and not data.error then SendNUIMessage({ action = 'data', data = data }) end
    end, { plate = curPlate, shop = curShop })
end

CreateThread(function()
    local m = Config.Marker
    while true do
        local wait = 700
        if not isOpen then
            local ped = PlayerPedId()
            local c = GetEntityCoords(ped)
            local near
            for _, sh in ipairs(Shops) do
                local d = #(c - vector3(sh.x + 0.0, sh.y + 0.0, sh.z + 0.0))
                if d < 20.0 then
                    wait = 0
                    DrawMarker(m.type, sh.x + 0.0, sh.y + 0.0, sh.z - 0.96, 0, 0, 0, 0, 0, 0,
                        m.size, m.size, m.size, m.r, m.g, m.b, m.a, false, false, 2, nil, nil, false)
                    if d < Config.Distance then near = sh end
                end
            end
            if near then
                BeginTextCommandDisplayHelp('STRING')
                AddTextComponentSubstringPlayerName('~INPUT_CONTEXT~ ' .. L('mech.help'))
                EndTextCommandDisplayHelp(0, false, true, -1)
                if IsControlJustReleased(0, 38) then
                    local veh = GetVehiclePedIsIn(ped, false)
                    if veh == 0 then
                        veh = GetClosestVehicle(c.x, c.y, c.z, 6.0, 0, 71)
                    end
                    local plate = plateOf(veh)
                    if plate then openDiag(near.id, plate) else Core.Notify(L('mech.err_novehicle'), 'error') end
                end
            end
        end
        Wait(wait)
    end
end)

-- Diagnostic scanner: read any nearby car without a shop.
RegisterNetEvent('v-mechanic:client:scan', function()
    local ped = PlayerPedId()
    local c = GetEntityCoords(ped)
    local veh = GetVehiclePedIsIn(ped, false)
    if veh == 0 then veh = GetClosestVehicle(c.x, c.y, c.z, 6.0, 0, 71) end
    local plate = plateOf(veh)
    if plate then openDiag(nil, plate) else Core.Notify(L('mech.err_novehicle'), 'error') end
end)

exports('ScanNearby', function()
    local ped = PlayerPedId()
    local c = GetEntityCoords(ped)
    local veh = GetVehiclePedIsIn(ped, false)
    if veh == 0 then veh = GetClosestVehicle(c.x, c.y, c.z, 6.0, 0, 71) end
    local plate = plateOf(veh)
    if plate then openDiag(nil, plate) else Core.Notify(L('mech.err_novehicle'), 'error') end
end)

-- ── NUI ────────────────────────────────────────────────────────
RegisterNUICallback('close', function(_, cb) close(); cb('ok') end)

RegisterNUICallback('replace', function(data, cb)
    Core.TriggerCallback('v-mechanic:replace', function(res)
        cb(res or false)
        if res and res.ok then
            if curPlate then ensure(curPlate).parts = res.parts end
            refresh()
        end
    end, { shop = curShop, plate = curPlate, part = data and data.part, account = data and data.account })
end)

RegisterNUICallback('patch', function(data, cb)
    Core.TriggerCallback('v-mechanic:patch', function(res)
        cb(res or false)
        if res and res.ok then
            if curPlate then ensure(curPlate).parts = res.parts end
            refresh()
        end
    end, { plate = curPlate, part = data and data.part })
end)

RegisterNUICallback('service', function(data, cb)
    Core.TriggerCallback('v-mechanic:service', function(res)
        cb(res or false)
        if res and res.ok then
            if curPlate then
                local st = ensure(curPlate)
                st.parts = res.parts; st.service = res.service
            end
            refresh()
        end
    end, { shop = curShop, plate = curPlate, account = data and data.account })
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    clearBlips()
    if isOpen then SetNuiFocus(false, false) end
end)
