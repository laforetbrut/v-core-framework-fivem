-- v-cityhall | client
-- Blip + clerk ped + marker at every city hall, a v-target zone, and the job desk NUI.
local Core = exports['v-core']:GetCore()
local isOpen = false
local peds, zones = {}, {}

local function strings()
    return Locales[(LocalPlayer.state and LocalPlayer.state.lang) or 'fr'] or Locales.fr or {}
end

local function L(key) return strings()[key] or key end

local function refresh()
    Core.TriggerCallback('v-cityhall:getJobs', function(data)
        if not data then return end
        SendNUIMessage({ action = 'data', data = data })
    end)
end

local function open()
    if isOpen then return end
    Core.TriggerCallback('v-cityhall:getJobs', function(data)
        if not data then return end
        isOpen = true
        SetNuiFocus(true, true)   -- focus is per-resource: only the page owner may take it
        exports['v-core']:MenuOpened()
        SendNUIMessage({ action = 'open', data = data, strings = strings() })
    end)
end

local function close()
    if not isOpen then return end
    isOpen = false
    SetNuiFocus(false, false)
    exports['v-core']:MenuClosed()
    SendNUIMessage({ action = 'close' })
end

-- ── World: blips, clerk peds, target zones ─────────────────────
local function spawnPed(l)
    if not Config.Ped then return end
    local model = joaat(Config.Ped)
    RequestModel(model)
    local t = GetGameTimer()
    while not HasModelLoaded(model) and GetGameTimer() - t < 8000 do Wait(10) end
    if not HasModelLoaded(model) then return end
    local ped = CreatePed(4, model, l.x, l.y, l.z - 1.0, l.h + 0.0, false, false)
    SetEntityInvincible(ped, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    FreezeEntityPosition(ped, true)
    SetPedDiesWhenInjured(ped, false)
    TaskStartScenarioInPlace(ped, 'WORLD_HUMAN_CLIPBOARD', 0, true)
    SetModelAsNoLongerNeeded(model)
    peds[#peds + 1] = ped
end

CreateThread(function()
    for _, l in ipairs(Config.Locations) do
        local b = AddBlipForCoord(l.x, l.y, l.z)
        SetBlipSprite(b, Config.Blip.sprite)
        SetBlipColour(b, Config.Blip.color)
        SetBlipScale(b, Config.Blip.scale)
        SetBlipAsShortRange(b, true)
        BeginTextCommandSetBlipName('STRING')
        AddTextComponentSubstringPlayerName(L('cityhall.blip'))
        EndTextCommandSetBlipName(b)

        spawnPed(l)

        -- The eye is the primary interaction surface; the E prompt below is the fallback.
        if GetResourceState('v-target') == 'started' then
            local ok, name = pcall(function()
                return exports['v-target']:AddSphereZone(nil, vector3(l.x, l.y, l.z), 2.2, {
                    { label = 'tgt.cityhall', icon = 'job', distance = 2.4, action = open },
                })
            end)
            if ok and name then zones[#zones + 1] = name end
        end
    end
end)

-- ── Proximity marker + E prompt ────────────────────────────────
CreateThread(function()
    local m = Config.Marker
    while true do
        local wait = 700
        if not isOpen then
            local c = GetEntityCoords(PlayerPedId())
            local near = false
            for _, l in ipairs(Config.Locations) do
                local d = #(c - vector3(l.x, l.y, l.z))
                if d < 12.0 then
                    wait = 0
                    DrawMarker(m.type, l.x, l.y, l.z - 0.96, 0, 0, 0, 0, 0, 0,
                        m.size, m.size, m.size, m.r, m.g, m.b, m.a, false, false, 2, nil, nil, false)
                    if d < Config.Distance then near = true end
                end
            end
            if near then
                BeginTextCommandDisplayHelp('STRING')
                AddTextComponentSubstringPlayerName('~INPUT_CONTEXT~ ' .. L('cityhall.help'))
                EndTextCommandDisplayHelp(0, false, true, -1)
                if IsControlJustReleased(0, 38) then open() end
            end
        end
        Wait(wait)
    end
end)

-- ── NUI callbacks ──────────────────────────────────────────────
RegisterNUICallback('close', function(_, cb) close(); cb('ok') end)

RegisterNUICallback('take', function(data, cb)
    Core.TriggerCallback('v-cityhall:take', function(res)
        cb(res or false)
        if res and res.ok then refresh() end
    end, data)
end)

-- Licences: the wallet and the counter. v-licenses owns every rule; we only relay.
RegisterNUICallback('licenses', function(_, cb)
    Core.TriggerCallback('v-licenses:mine', function(data)
        if data then SendNUIMessage({ action = 'licenses', data = data }) end
        cb('ok')
    end)
end)

RegisterNUICallback('buyLicense', function(data, cb)
    Core.TriggerCallback('v-licenses:buy', function(res)
        cb(res or false)
        if res and res.ok then
            Core.TriggerCallback('v-licenses:mine', function(fresh)
                if fresh then SendNUIMessage({ action = 'licenses', data = fresh }) end
            end)
        end
    end, data)
end)

RegisterNUICallback('resign', function(_, cb)
    Core.TriggerCallback('v-cityhall:resign', function(res)
        cb(res or false)
        if res and res.ok then refresh() end
    end)
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for _, p in ipairs(peds) do if DoesEntityExist(p) then DeleteEntity(p) end end
    for _, z in ipairs(zones) do pcall(function() exports['v-target']:RemoveZone(z) end) end
    if isOpen then SetNuiFocus(false, false) end
end)
