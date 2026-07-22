-- v-garages | client
-- Blips + markers + the garage NUI. Rebuilds live when an admin edits a garage.
local Core = exports['v-core']:GetCore()

local Garages = Config.Garages
local blips = {}
local isOpen, curGarage = false, nil

local function strings()
    return Locales[(LocalPlayer.state and LocalPlayer.state.lang) or 'fr'] or Locales.fr or {}
end
local function L(k) return strings()[k] or k end

-- ── Blips ──────────────────────────────────────────────────────
local function clearBlips()
    for _, b in ipairs(blips) do if DoesBlipExist(b) then RemoveBlip(b) end end
    blips = {}
end

local function buildBlips()
    clearBlips()
    for _, g in ipairs(Garages) do
        if g.blip ~= 0 then
            local b = AddBlipForCoord(g.x + 0.0, g.y + 0.0, g.z + 0.0)
            SetBlipSprite(b, Config.Blip[g.type] or Config.Blip.public)
            SetBlipColour(b, Config.BlipColor[g.type] or Config.BlipColor.public)
            SetBlipScale(b, 0.7); SetBlipAsShortRange(b, true)
            BeginTextCommandSetBlipName('STRING')
            AddTextComponentSubstringPlayerName(g.label or L('gar.blip'))
            EndTextCommandSetBlipName(b)
            blips[#blips + 1] = b
        end
    end
end

RegisterNetEvent('v-garages:client:garages', function(list)
    if type(list) ~= 'table' then return end
    Garages = list
    buildBlips()
end)

CreateThread(function()
    Wait(2500)
    TriggerServerEvent('v-garages:server:request')
    buildBlips()
end)

-- ── Open ───────────────────────────────────────────────────────
local function open(g)
    if isOpen then return end
    Core.TriggerCallback('v-garages:list', function(data)
        if not data or data.error then
            if data and data.error == 'nojob' then Core.Notify(L('gar.nojob'), 'error') end
            return
        end
        isOpen, curGarage = true, g.id
        SetNuiFocus(true, true)   -- focus is per-resource: only the page owner may take it
        exports['v-core']:MenuOpened()
        SendNUIMessage({ action = 'open', data = data, strings = strings() })
    end, { garage = g.id })
end

local function close()
    if not isOpen then return end
    isOpen, curGarage = false, nil
    SetNuiFocus(false, false)
    exports['v-core']:MenuClosed()
    SendNUIMessage({ action = 'close' })
end

local function refresh()
    if not curGarage then return end
    Core.TriggerCallback('v-garages:list', function(data)
        if data and not data.error then SendNUIMessage({ action = 'data', data = data }) end
    end, { garage = curGarage })
end

-- ── Marker + prompt. Inside a vehicle the prompt becomes "store". ──
CreateThread(function()
    local m = Config.Marker
    while true do
        local wait = 700
        if not isOpen then
            local ped = PlayerPedId()
            local c = GetEntityCoords(ped)
            local near
            for _, g in ipairs(Garages) do
                local d = #(c - vector3(g.x + 0.0, g.y + 0.0, g.z + 0.0))
                if d < 20.0 then
                    wait = 0
                    DrawMarker(m.type, g.x + 0.0, g.y + 0.0, g.z - 0.96, 0, 0, 0, 0, 0, 0,
                        m.size, m.size, m.size, m.r, m.g, m.b, m.a, false, false, 2, nil, nil, false)
                    if d < Config.Distance then near = g end
                end
            end
            if near then
                local veh = GetVehiclePedIsIn(ped, false)
                local driving = veh ~= 0 and GetPedInVehicleSeat(veh, -1) == ped
                BeginTextCommandDisplayHelp('STRING')
                AddTextComponentSubstringPlayerName('~INPUT_CONTEXT~ ' ..
                    (driving and L('gar.help_store') or L('gar.help_open')))
                EndTextCommandDisplayHelp(0, false, true, -1)
                if IsControlJustReleased(0, 38) then
                    if driving then
                        -- Store what we are actually sitting in; the server re-checks the
                        -- plate, the ownership and the vehicle's own position.
                        local plate = (GetVehicleNumberPlateText(veh) or ''):gsub('%s+$', '')
                        Core.TriggerCallback('v-garages:store', function(res)
                            if res and res.ok then Core.Notify(L('gar.stored'), 'success')
                            else Core.Notify(L('gar.err_' .. ((res and res.error) or 'x')), 'error') end
                        end, {
                            garage = near.id, plate = plate,
                            netid = VehToNet(veh),
                            state = {
                                props  = exports['v-vehicles']:GetProps(veh),
                                fuel   = exports['v-vehicles']:GetFuel(veh),
                                engine = math.floor(GetVehicleEngineHealth(veh)),
                                body   = math.floor(GetVehicleBodyHealth(veh)),
                            },
                        })
                    else
                        open(near)
                    end
                end
            end
        end
        Wait(wait)
    end
end)

-- ── NUI ────────────────────────────────────────────────────────
RegisterNUICallback('close', function(_, cb) close(); cb('ok') end)

RegisterNUICallback('take', function(data, cb)
    Core.TriggerCallback('v-garages:take', function(res)
        cb(res or false)
        if res and res.ok then close() end
    end, { garage = curGarage, plate = data and data.plate })
end)

RegisterNUICallback('refresh', function(_, cb) refresh(); cb('ok') end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    clearBlips()
    if isOpen then SetNuiFocus(false, false) end
end)
