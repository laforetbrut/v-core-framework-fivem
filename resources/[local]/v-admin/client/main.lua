-- v-admin | client
local Core = exports['v-core']:GetCore()
local isOpen = false

local function strings()
    return Locales[(LocalPlayer.state and LocalPlayer.state.lang) or 'fr'] or Locales.fr or {}
end

-- ── Panel open / close (keybind F10 — this server has no chat) ──
local function closePanel()
    if not isOpen then return end
    isOpen = false
    exports['v-core']:CloseMenu()
    SendNUIMessage({ action = 'close' })
end

RegisterCommand('vadmin_panel', function()
    if isOpen then closePanel(); return end
    Core.TriggerCallback('v-admin:open', function(res)
        if not res or not res.ok then return end   -- silently ignored for non-admins
        isOpen = true
        exports['v-core']:OpenMenu()
        SendNUIMessage({ action = 'open', strings = strings(), super = res.super, weathers = res.weathers })
    end)
end, false)
RegisterKeyMapping('vadmin_panel', 'Admin: management panel', 'keyboard', 'F10')

RegisterNUICallback('close', function(_, cb) closePanel(); cb('ok') end)

-- Data relays (NUI -> server callbacks).
local relays = { dash = 'v-admin:dashboard', players = 'v-admin:players', resources = 'v-admin:resources' }
for cbName, serverCb in pairs(relays) do
    RegisterNUICallback(cbName, function(_, cb)
        Core.TriggerCallback(serverCb, function(res) cb(res or false) end)
    end)
end

RegisterNUICallback('logs', function(data, cb)
    Core.TriggerCallback('v-admin:logs', function(res) cb(res or {}) end, data.filter)
end)

RegisterNUICallback('action', function(data, cb)
    Core.TriggerCallback('v-admin:action', function(ok) cb(ok and true or false) end, data)
end)

-- ── Effects executed on this client ────────────────────────────
RegisterNetEvent('v-admin:client:heal', function()
    local ped = PlayerPedId()
    if IsEntityDead(ped) then
        local c = GetEntityCoords(ped)
        NetworkResurrectLocalPlayer(c.x, c.y, c.z, GetEntityHeading(ped), true, false)
        ped = PlayerPedId()
    end
    SetEntityHealth(ped, GetEntityMaxHealth(ped))
    SetPedArmour(ped, 100)
    ClearPedBloodDamage(ped)
    pcall(function() exports['v-status']:Heal() end)
    Core.Notify(strings()['adm.healed'] or 'You have been healed.', 'success')
end)

RegisterNetEvent('v-admin:client:freeze', function(state)
    FreezeEntityPosition(PlayerPedId(), state and true or false)
    Core.Notify(state and (strings()['adm.frozen'] or 'You have been frozen.')
        or (strings()['adm.unfrozen'] or 'You have been unfrozen.'), 'warning')
end)

RegisterNetEvent('v-admin:client:teleport', function(x, y, z)
    local ped = PlayerPedId()
    DoScreenFadeOut(250); Wait(300)
    SetEntityCoordsNoOffset(ped, x, y, z + 0.5, false, false, false)
    RequestCollisionAtCoord(x, y, z)
    local t = 0
    while not HasCollisionLoadedAroundEntity(ped) and t < 60 do Wait(50); t = t + 1 end
    DoScreenFadeIn(300)
end)

RegisterNetEvent('v-admin:client:car', function(model)
    local hash = joaat(model)
    if not IsModelInCdimage(hash) or not IsModelAVehicle(hash) then
        Core.Notify(strings()['adm.badmodel'] or 'Unknown vehicle model.', 'error'); return
    end
    RequestModel(hash)
    local t = 0
    while not HasModelLoaded(hash) and t < 100 do Wait(30); t = t + 1 end
    if not HasModelLoaded(hash) then return end
    local ped = PlayerPedId()
    local c = GetEntityCoords(ped)
    local veh = CreateVehicle(hash, c.x, c.y, c.z, GetEntityHeading(ped), true, false)
    SetPedIntoVehicle(ped, veh, -1)
    SetVehicleEngineOn(veh, true, true, false)
    SetModelAsNoLongerNeeded(hash)
end)

-- ── World sync (weather / time), also applied on late join ─────
local function applyWeather(w)
    if type(w) ~= 'string' then return end
    pcall(function()
        SetWeatherTypeOvertimePersist(w, 6.0)
        Wait(6100)
        ClearWeatherTypePersist()
        SetWeatherTypeNowPersist(w)
    end)
end

RegisterNetEvent('v-admin:client:weather', function(w) CreateThread(function() applyWeather(w) end) end)

RegisterNetEvent('v-admin:client:time', function(h, freeze)
    NetworkOverrideClockTime(h, 0, 0)
    PauseClock(freeze and true or false)
end)

CreateThread(function()
    Wait(3000)
    local w = GlobalState.vweather
    if w then applyWeather(w) end
    local ti = GlobalState.vtime
    if ti and ti.h then NetworkOverrideClockTime(ti.h, 0, 0); PauseClock(ti.freeze and true or false) end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    exports['v-core']:CloseMenu()
end)
