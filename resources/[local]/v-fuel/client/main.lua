-- v-fuel | client
-- Owns fuel CONSUMPTION (v-vehicles only stores the number) and drives the pump.
local Core = exports['v-core']:GetCore()

local Stations = Config.Stations
local blips = {}
local isOpen, curStation, curVeh = false, nil, nil
local pumping = false

local function strings()
    return Locales[(LocalPlayer.state and LocalPlayer.state.lang) or 'fr'] or Locales.fr or {}
end
local function L(k, ...)
    local s = strings()[k] or k
    if select('#', ...) > 0 then return (s:format(...)) end
    return s
end

-- ── What fuel does this vehicle take? ──────────────────────────
local elec, dieselM = {}, {}
for _, m in ipairs(Config.ElectricModels) do elec[joaat(m)] = true end
for _, m in ipairs(Config.DieselModels) do dieselM[joaat(m)] = true end

local function fuelTypeOf(veh)
    if not veh or veh == 0 or not DoesEntityExist(veh) then return 'regular' end
    local model = GetEntityModel(veh)
    if elec[model] then return 'electric' end
    if dieselM[model] then return 'diesel' end
    if Config.DieselClasses[GetVehicleClass(veh)] then return 'diesel' end
    return 'regular'
end

local function tankOf(veh)
    if not veh or veh == 0 then return Config.DefaultTank end
    return Config.TankByClass[GetVehicleClass(veh)] or Config.DefaultTank
end

exports('GetFuelType', function(veh) return fuelTypeOf(veh) end)
exports('GetTankSize', function(veh) return tankOf(veh) end)
exports('IsElectric', function(veh) return fuelTypeOf(veh) == 'electric' end)

--- Charge speed at a given state of charge. Past the taper knee the cells deliberately
--- slow down — that is real behaviour, and it is why "charge to 80 %" is a habit.
local function chargeRate(kw, pct)
    local rate = kw * Config.EV.kwhPerSecondPerKw
    if pct >= Config.EV.taperFrom then rate = rate * Config.EV.taperMult end
    return rate
end

-- ── Consumption ────────────────────────────────────────────────
-- v-vehicles keeps the stored percentage; we decide how fast it falls. Load is derived
-- from actual speed against the model's top speed, so idling barely costs anything and
-- flooring a supercar costs a lot.
CreateThread(function()
    while true do
        Wait(5000)   -- 12 ticks per minute
        local ped = PlayerPedId()
        local veh = GetVehiclePedIsIn(ped, false)
        if veh ~= 0 and GetPedInVehicleSeat(veh, -1) == ped and GetIsVehicleEngineRunning(veh) then
            local cls = GetVehicleClass(veh)
            if cls ~= 13 then   -- bicycles have no tank
                local ftype = fuelTypeOf(veh)
                local rate  = (Config.Types[ftype] or {}).rate or 1.0
                local mult  = Config.DrainByClass[cls] or 1.0
                local speed = GetEntitySpeed(veh)
                local top   = math.max(1.0, GetVehicleEstimatedMaxSpeed(veh))
                local load  = math.min(1.0, speed / top)
                -- idle floor + the speed-driven part, per minute, converted to this tick
                local perMin = Config.IdleDrain + (Config.BaseDrain * load * mult * rate)
                local drop   = perMin / 12.0
                local cur    = exports['v-vehicles']:GetFuel(veh)
                local now    = math.max(0, cur - drop)
                exports['v-vehicles']:SetFuel(veh, now)
                if now <= 0 then
                    SetVehicleEngineOn(veh, false, true, true)
                    Core.Notify(L('fuel.empty'), 'error')
                elseif cur > 15 and now <= 15 then
                    Core.Notify(L('fuel.low'), 'warning')
                end
            end
        end
    end
end)

-- Admin changed a tunable: the client owns consumption, so it needs the new numbers.
RegisterNetEvent('v-fuel:client:tunables', function(t)
    if type(t) ~= 'table' then return end
    Config.BaseDrain = tonumber(t.baseDrain) or Config.BaseDrain
    Config.IdleDrain = tonumber(t.idleDrain) or Config.IdleDrain
    Config.FlowRate  = tonumber(t.flowRate) or Config.FlowRate
    Config.EV.taperFrom = tonumber(t.taperFrom) or Config.EV.taperFrom
    if t.regen ~= nil then Config.EV.regen.enabled = t.regen and true or false end
end)

-- ── Regenerative braking (electric only) ───────────────────────
-- Slowing an EV puts a little charge back. Small on purpose: it should reward a smooth
-- driver, not remove the need to charge.
CreateThread(function()
    if not Config.EV.regen.enabled then return end
    local lastSpeed = 0.0
    while true do
        Wait(1000)
        local ped = PlayerPedId()
        local veh = GetVehiclePedIsIn(ped, false)
        if veh ~= 0 and GetPedInVehicleSeat(veh, -1) == ped and fuelTypeOf(veh) == 'electric' then
            local speed = GetEntitySpeed(veh)
            local slowing = lastSpeed - speed
            if slowing > 1.5 and speed > 1.0 then
                local cur = exports['v-vehicles']:GetFuel(veh)
                if cur < 100 then
                    exports['v-vehicles']:SetFuel(veh, math.min(100, cur + Config.EV.regen.perBrakeSecond * slowing))
                end
            end
            lastSpeed = speed
        else
            lastSpeed = 0.0
        end
    end
end)

-- ── Blips ──────────────────────────────────────────────────────
local function clearBlips()
    for _, b in ipairs(blips) do if DoesBlipExist(b) then RemoveBlip(b) end end
    blips = {}
end

local function isEV(st) return tostring(st.types or ''):find('electric') ~= nil and not tostring(st.types):find('regular') end

local function buildBlips()
    clearBlips()
    for _, st in ipairs(Stations) do
        if st.blip ~= 0 then
            local b = AddBlipForCoord(st.x + 0.0, st.y + 0.0, st.z + 0.0)
            local ev = isEV(st)
            SetBlipSprite(b, ev and Config.Blip.evSprite or Config.Blip.sprite)
            SetBlipColour(b, ev and Config.Blip.evColor or Config.Blip.color)
            SetBlipScale(b, Config.Blip.scale); SetBlipAsShortRange(b, true)
            BeginTextCommandSetBlipName('STRING')
            AddTextComponentSubstringPlayerName(st.label or L('fuel.blip'))
            EndTextCommandSetBlipName(b)
            blips[#blips + 1] = b
        end
    end
end

RegisterNetEvent('v-fuel:client:stations', function(list)
    if type(list) ~= 'table' then return end
    Stations = list
    buildBlips()
end)

CreateThread(function()
    Wait(2500)
    TriggerServerEvent('v-fuel:server:request')
    buildBlips()
end)

-- ── Pump ───────────────────────────────────────────────────────
local function nearestVehicle()
    local c = GetEntityCoords(PlayerPedId())
    local veh = GetClosestVehicle(c.x, c.y, c.z, Config.NozzleRange, 0, 71)
    if veh and veh ~= 0 and DoesEntityExist(veh) then return veh end
    return nil
end

local function open(st)
    if isOpen then return end
    curVeh = nearestVehicle()
    local info = nil
    if curVeh then
        info = { model = GetDisplayNameFromVehicleModel(GetEntityModel(curVeh)),
                 plate = (GetVehicleNumberPlateText(curVeh) or ''):gsub('%s+$', ''),
                 accepts = fuelTypeOf(curVeh), tank = tankOf(curVeh),
                 fuel = math.floor(exports['v-vehicles']:GetFuel(curVeh)) }
    end
    Core.TriggerCallback('v-fuel:open', function(data)
        if not data or data.error then
            if data and data.error == 'far' then Core.Notify(L('fuel.err_far'), 'error') end
            return
        end
        isOpen, curStation = true, st.id
        data.vehicle = info
        SetNuiFocus(true, true)   -- focus is per-resource: only the page owner may take it
        exports['v-core']:MenuOpened()
        SendNUIMessage({ action = 'open', data = data, strings = strings() })
    end, { station = st.id, vehicle = info })
end

local function close()
    if not isOpen then return end
    isOpen, curStation, curVeh = false, nil, nil
    SetNuiFocus(false, false)
    exports['v-core']:MenuClosed()
    SendNUIMessage({ action = 'close' })
end

CreateThread(function()
    local m = Config.Marker
    while true do
        local wait = 700
        if not isOpen and not pumping then
            local c = GetEntityCoords(PlayerPedId())
            local near
            for _, st in ipairs(Stations) do
                local d = #(c - vector3(st.x + 0.0, st.y + 0.0, st.z + 0.0))
                if d < 18.0 then
                    wait = 0
                    DrawMarker(m.type, st.x + 0.0, st.y + 0.0, st.z - 0.96, 0, 0, 0, 0, 0, 0,
                        m.size, m.size, m.size, m.r, m.g, m.b, m.a, false, false, 2, nil, nil, false)
                    if d < Config.Distance then near = st end
                end
            end
            if near then
                BeginTextCommandDisplayHelp('STRING')
                AddTextComponentSubstringPlayerName('~INPUT_CONTEXT~ ' .. L('fuel.help'))
                EndTextCommandDisplayHelp(0, false, true, -1)
                if IsControlJustReleased(0, 38) then open(near) end
            end
        end
        Wait(wait)
    end
end)

-- ── Running the nozzle ─────────────────────────────────────────
-- The bar the player watches is here; the money and the fuel that lands in the tank are
-- decided by the server from the litres reported at the end.
RegisterNUICallback('pump', function(data, cb)
    if pumping or not curStation or not curVeh or not DoesEntityExist(curVeh) then cb(false); return end
    local ftype = tostring(data and data.type or '')
    local want  = math.max(0, tonumber(data and data.litres) or 0)
    local account = (data and data.account == 'bank') and 'bank' or 'cash'
    if want <= 0 or not Config.Types[ftype] then cb(false); return end

    local accepts = fuelTypeOf(curVeh)
    -- premium is accepted anywhere regular is: same pump family, better octane
    local wrong = not (ftype == accepts or (accepts == 'regular' and ftype == 'premium'))

    pumping = true
    close()
    local connKey = tostring((data and data.connector) or 'ac')
    local conn = Config.EV.connectors[connKey] or Config.EV.connectors.ac
    local flow = (ftype == 'electric') and (conn.kw * Config.EV.kwhPerSecondPerKw) or Config.FlowRate
    local tank = tankOf(curVeh)
    local drawn, veh = 0.0, curVeh

    CreateThread(function()
        local ped = PlayerPedId()
        FreezeEntityPosition(ped, true)
        while drawn < want do
            if not DoesEntityExist(veh) then break end
            if #(GetEntityCoords(ped) - GetEntityCoords(veh)) > Config.NozzleRange + 2.0 then break end
            local step = flow
            if ftype == 'electric' then
                -- taper on the CURRENT state of charge, not the starting one
                local soc = exports['v-vehicles']:GetFuel(veh) + (drawn / math.max(1, tank)) * 100
                step = chargeRate(conn.kw, soc)
            end
            drawn = math.min(want, drawn + step * 0.25)
            SendNUIMessage({ action = 'pumping', litres = drawn, want = want })
            Wait(250)
        end
        FreezeEntityPosition(ped, false)
        SendNUIMessage({ action = 'pumpDone' })

        Core.TriggerCallback('v-fuel:refuel', function(res)
            pumping = false
            if not res or not res.ok then
                Core.Notify(L('fuel.err_' .. ((res and res.error) or 'x')), 'error'); return
            end
            if res.wrong then return end   -- the server already told them, and damaged the engine
            if DoesEntityExist(veh) then
                local pct = math.min(100, exports['v-vehicles']:GetFuel(veh) + (res.litres / tank) * 100)
                exports['v-vehicles']:SetFuel(veh, pct)
            end
        end, { station = curStation or '', type = ftype, litres = drawn, tank = tank,
               netid = VehToNet(veh), account = account, wrongFuel = wrong, connector = connKey })
    end)
    cb('ok')
end)

RegisterNetEvent('v-fuel:client:wrongFuel', function(netid, damage)
    if not NetworkDoesEntityExistWithNetworkId(netid) then return end
    local veh = NetToVeh(netid)
    if not veh or veh == 0 or not DoesEntityExist(veh) then return end
    SetVehicleEngineHealth(veh, math.max(100.0, GetVehicleEngineHealth(veh) - (tonumber(damage) or 100)))
end)

RegisterNUICallback('fillCan', function(_, cb)
    Core.TriggerCallback('v-fuel:fillCan', function(res)
        cb(res or false)
        if res and res.error and res.error ~= 'funds' then Core.Notify(L('fuel.err_' .. res.error), 'error') end
    end, { station = curStation })
end)

RegisterNUICallback('close', function(_, cb) close(); cb('ok') end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    clearBlips()
    if isOpen then SetNuiFocus(false, false) end
    FreezeEntityPosition(PlayerPedId(), false)
end)

-- ── Theme ──────────────────────────────────────────────────────
-- A NUI page can only be messaged by the resource that owns it, so v-ui cannot reach this
-- one directly: it publishes a version and each module forwards it into its own page.
local function pushTheme()
    if GetResourceState('v-ui') ~= 'started' then return end
    SendNUIMessage({ action = 'v-ui:theme', version = exports['v-ui']:Version() })
end

AddEventHandler('v-ui:client:themeChanged', function() pushTheme() end)
CreateThread(function() Wait(4000); pushTheme() end)
