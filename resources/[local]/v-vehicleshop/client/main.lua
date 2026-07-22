-- v-vehicleshop | client
-- Dealership floor: blips, the panel, the showroom preview (borrowed from v-vehicles) and
-- the test drive. Nothing here decides anything — the server owns every gate and the money.
local Core = exports['v-core']:GetCore()

local Dealers = Config.Dealers
local blips = {}
local isOpen, curDealer = false, nil
local testing, testUntil, testVeh, testReturn = false, 0, nil, nil

local function strings()
    return Locales[(LocalPlayer.state and LocalPlayer.state.lang) or 'fr'] or Locales.fr or {}
end
local function L(k, ...)
    local s = strings()[k] or k
    if select('#', ...) > 0 then return (s:format(...)) end
    return s
end

-- ── Blips ──────────────────────────────────────────────────────
local function clearBlips()
    for _, b in ipairs(blips) do if DoesBlipExist(b) then RemoveBlip(b) end end
    blips = {}
end

local function buildBlips()
    clearBlips()
    for _, d in ipairs(Dealers) do
        if d.blip ~= 0 then
            local b = AddBlipForCoord(d.x + 0.0, d.y + 0.0, d.z + 0.0)
            SetBlipSprite(b, Config.Blip.sprite); SetBlipColour(b, Config.Blip.color)
            SetBlipScale(b, Config.Blip.scale); SetBlipAsShortRange(b, true)
            BeginTextCommandSetBlipName('STRING')
            AddTextComponentSubstringPlayerName(d.label or L('shop.blip'))
            EndTextCommandSetBlipName(b)
            blips[#blips + 1] = b
        end
    end
end

RegisterNetEvent('v-vehicleshop:client:dealers', function(list)
    if type(list) ~= 'table' then return end
    Dealers = list
    buildBlips()
end)

CreateThread(function()
    Wait(3000)
    TriggerServerEvent('v-vehicleshop:server:request')
    buildBlips()
end)

-- ── Panel ──────────────────────────────────────────────────────
local function open(d)
    if isOpen or testing then return end
    Core.TriggerCallback('v-vehicleshop:open', function(data)
        if not data or data.error then
            Core.Notify(L('shop.err_' .. ((data and data.error) or 'x')), 'error'); return
        end
        isOpen, curDealer = true, d.id
        SetNuiFocus(true, true)   -- focus is per-resource: only the page owner may take it
        exports['v-core']:MenuOpened()
        SendNUIMessage({ action = 'open', data = data, strings = strings() })
    end, { dealer = d.id })
end

local function close()
    if not isOpen then return end
    isOpen, curDealer = false, nil
    exports['v-vehicles']:ClosePreview()
    SetNuiFocus(false, false)
    exports['v-core']:MenuClosed()
    SendNUIMessage({ action = 'close' })
end

local function refresh()
    if not curDealer then return end
    Core.TriggerCallback('v-vehicleshop:open', function(data)
        if data and not data.error then SendNUIMessage({ action = 'data', data = data }) end
    end, { dealer = curDealer })
end

CreateThread(function()
    local m = Config.Marker
    while true do
        local wait = 700
        if not isOpen and not testing then
            local c = GetEntityCoords(PlayerPedId())
            local near
            for _, d in ipairs(Dealers) do
                local dist = #(c - vector3(d.x + 0.0, d.y + 0.0, d.z + 0.0))
                if dist < 20.0 then
                    wait = 0
                    DrawMarker(m.type, d.x + 0.0, d.y + 0.0, d.z - 0.96, 0, 0, 0, 0, 0, 0,
                        m.size, m.size, m.size, m.r, m.g, m.b, m.a, false, false, 2, nil, nil, false)
                    if dist < Config.Distance then near = d end
                end
            end
            if near then
                BeginTextCommandDisplayHelp('STRING')
                AddTextComponentSubstringPlayerName('~INPUT_CONTEXT~ ' .. L('shop.help'))
                EndTextCommandDisplayHelp(0, false, true, -1)
                if IsControlJustReleased(0, 38) then open(near) end
            end
        end
        Wait(wait)
    end
end)

-- ── Test drive ─────────────────────────────────────────────────
-- A LOCAL vehicle on a timer, returned to exactly where you started. It is never
-- networked and never becomes an owned car, so there is nothing to keep or dupe.
local function endTest()
    if not testing then return end
    testing = false
    if testVeh and DoesEntityExist(testVeh) then
        SetEntityAsMissionEntity(testVeh, true, true)
        DeleteVehicle(testVeh)
    end
    testVeh = nil
    local ped = PlayerPedId()
    if testReturn then
        SetEntityCoords(ped, testReturn.x, testReturn.y, testReturn.z, false, false, false, false)
        SetEntityHeading(ped, testReturn.w)
        testReturn = nil
    end
    SendNUIMessage({ action = 'testEnd' })
    Core.Notify(L('shop.test_over'), 'info')
end

local function startTest(model, dealer)
    if testing then return end
    local d
    for _, x in ipairs(Dealers) do if x.id == dealer then d = x end end
    if not d then return end

    local hash = joaat(model)
    if not IsModelInCdimage(hash) or not IsModelAVehicle(hash) then
        Core.Notify(L('shop.err_unknown'), 'error'); return
    end
    RequestModel(hash)
    local tries = 0
    while not HasModelLoaded(hash) and tries < 150 do Wait(20); tries = tries + 1 end
    if not HasModelLoaded(hash) then Core.Notify(L('shop.err_unknown'), 'error'); return end

    local ped = PlayerPedId()
    local c = GetEntityCoords(ped)
    testReturn = vector4(c.x, c.y, c.z, GetEntityHeading(ped))

    -- `false, false` = not networked: this car exists only for the person driving it
    testVeh = CreateVehicle(hash, d.sx + 0.0, d.sy + 0.0, d.sz + 0.0, (d.sh or 0.0) + 0.0, false, false)
    SetModelAsNoLongerNeeded(hash)
    if not testVeh or testVeh == 0 then Core.Notify(L('shop.err_unknown'), 'error'); return end

    SetVehicleNumberPlateText(testVeh, 'TESTDRV')
    SetVehicleEngineOn(testVeh, true, true, false)
    TaskWarpPedIntoVehicle(ped, testVeh, -1)

    testing = true
    testUntil = GetGameTimer() + Config.TestDrive.seconds * 1000
    close()
    Core.Notify(L('shop.test_start', Config.TestDrive.seconds), 'info')

    CreateThread(function()
        while testing do
            local left = math.max(0, math.ceil((testUntil - GetGameTimer()) / 1000))
            SendNUIMessage({ action = 'testTick', left = left })
            if left <= 0 then endTest(); break end
            Wait(500)
        end
    end)
end

-- ── NUI ────────────────────────────────────────────────────────
RegisterNUICallback('close', function(_, cb) close(); cb('ok') end)

RegisterNUICallback('preview', function(data, cb)
    if not isOpen then cb(false); return end
    if not data or not data.model then exports['v-vehicles']:ClosePreview(); cb('ok'); return end
    cb(exports['v-vehicles']:OpenPreview(data.model) and 'ok' or false)
end)

RegisterNUICallback('previewRotate', function(data, cb)
    exports['v-vehicles']:RotatePreview((data and data.dx) or 0); cb('ok')
end)

RegisterNUICallback('previewZoom', function(data, cb)
    exports['v-vehicles']:ZoomPreview((data and data.dz) or 0); cb('ok')
end)

RegisterNUICallback('test', function(data, cb)
    cb('ok')
    if data and data.model then startTest(tostring(data.model), curDealer) end
end)

RegisterNUICallback('buy', function(data, cb)
    Core.TriggerCallback('v-vehicleshop:buy', function(res)
        cb(res or false)
        if res and res.ok then refresh() end
    end, { dealer = curDealer, model = data and data.model, account = data and data.account })
end)

RegisterNUICallback('mine', function(_, cb)
    Core.TriggerCallback('v-vehicleshop:mine', function(res)
        cb(res or false)
    end, { dealer = curDealer })
end)

RegisterNUICallback('sell', function(data, cb)
    Core.TriggerCallback('v-vehicleshop:sell', function(res)
        cb(res or false)
        if res and res.ok then refresh() end
    end, { dealer = curDealer, plate = data and data.plate })
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    clearBlips()
    if testing then endTest() end
    if isOpen then SetNuiFocus(false, false) end
end)

-- ══════════════════════════════════════════════════════════════════
--  Automatic vehicle scan (admin)
-- ══════════════════════════════════════════════════════════════════
-- Enumerates every vehicle model the CLIENT can actually spawn — base game plus any addon
-- pack installed on the server — and reports the ones missing from the catalogue, with
-- their real class, display name and performance figures. That is what makes adding a
-- car pack a two-click job instead of hand-writing a config table.
--
-- It runs client-side because only the client has the model natives; the server decides
-- what to do with the result and re-validates everything before it lands in the DB.

-- GTA class id -> our shop category. Anything unmapped lands in `utility` so it is
-- visible and reclassifiable rather than silently dropped.
local CLASS_CAT = {
    [0] = 'compacts', [1] = 'sedans', [2] = 'suvs', [3] = 'coupes', [4] = 'muscle',
    [5] = 'muscle', [6] = 'sports', [7] = 'super', [8] = 'motorcycles', [9] = 'offroad',
    [10] = 'industrial', [11] = 'utility', [12] = 'vans', [14] = 'boats',
    [15] = 'air', [16] = 'air', [17] = 'utility', [18] = 'utility', [19] = 'utility',
    [20] = 'industrial',
}

--- Suggest a price from the model's own performance. Deliberately rough: it gives an
--- operator a sane starting number to edit, not a final answer.
local function suggestPrice(model, class)
    local top   = GetVehicleModelMaxSpeed(model) or 0.0
    local accel = GetVehicleModelAcceleration(model) or 0.0
    local brake = GetVehicleModelMaxBraking(model) or 0.0
    local score = (top * 2.2) + (accel * 180.0) + (brake * 40.0)
    local base  = math.floor(score * 900)
    if class == 7 then base = base * 3                     -- super
    elseif class == 15 or class == 16 then base = base * 4 -- helicopters / planes
    end
    base = math.floor(base / 500) * 500           -- round to something a human would type
    return math.max(5000, math.min(3000000, base))
end

local function runScan()
    CreateThread(function()
        local found, seen = {}, {}
        for _, model in ipairs(GetAllVehicleModels() or {}) do
            local name = tostring(model):lower()
            if not seen[name] then
                seen[name] = true
                local hash = joaat(name)
                if IsModelInCdimage(hash) and IsModelAVehicle(hash) then
                    local class = GetVehicleClassFromName(hash)
                    -- trains, trailers and the like have no business in a showroom
                    if class ~= 21 and class ~= 13 and CLASS_CAT[class] then
                        local label = GetLabelText(GetDisplayNameFromVehicleModel(hash))
                        if not label or label == 'NULL' or label == '' then
                            label = GetDisplayNameFromVehicleModel(hash)
                        end
                        found[#found + 1] = {
                            model = name,
                            label = label,
                            cat = CLASS_CAT[class],
                            class = class,
                            price = suggestPrice(hash, class),
                            top = math.floor((GetVehicleModelMaxSpeed(hash) or 0) * 3.6 + 0.5),
                            seats = GetVehicleModelNumberOfSeats(hash) or 0,
                        }
                    end
                end
            end
            if #found % 120 == 0 then Wait(0) end   -- never block a frame for long
        end
        TriggerServerEvent('v-vehicleshop:server:scanResult', found)
    end)
end

-- v-admin asks for the scan; the panel that displays the result lives there too.
AddEventHandler('v-vehicleshop:client:doScan', function() runScan() end)
RegisterNetEvent('v-vehicleshop:client:scanDone', function(n)
    Core.Notify(L('shop.scan_done', n), 'success')
end)
exports('ScanVehicles', function() runScan() end)
