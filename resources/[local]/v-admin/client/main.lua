-- v-admin | client
local Core = exports['v-core']:GetCore()
local isOpen = false
local amAdmin = false   -- set when the panel opens as an admin; gates the self-tools

local function strings()
    return Locales[(LocalPlayer.state and LocalPlayer.state.lang) or 'fr'] or Locales.fr or {}
end

-- ── Panel open / close (keybind F10 — this server has no chat) ──
local function closePanel()
    if not isOpen then return end
    isOpen = false
    SetNuiFocus(false, false)
    exports['v-core']:MenuClosed()
    SendNUIMessage({ action = 'close' })
end

RegisterCommand('vadmin_panel', function()
    if isOpen then closePanel(); return end
    Core.TriggerCallback('v-admin:open', function(res)
        if not res or not res.ok then return end   -- silently ignored for non-admins
        isOpen = true
        amAdmin = true
        SetNuiFocus(true, true)   -- focus is per-resource: only the page owner may take it
        exports['v-core']:MenuOpened()
        SendNUIMessage({ action = 'open', strings = strings(), super = res.super, weathers = res.weathers,
            tools = { noclip = noclipOn, god = godOn, invisible = invisOn, esp = espOn } })
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

-- ── World editor relays (blips / shop locations / jobs) -> v-world ──
RegisterNUICallback('worldList', function(data, cb)
    Core.TriggerCallback('v-world:list', function(res) cb(res or false) end, data and data.domain)
end)

RegisterNUICallback('worldSave', function(data, cb)
    Core.TriggerCallback('v-world:save', function(res) cb(res or false) end, data)
end)

RegisterNUICallback('worldDelete', function(data, cb)
    Core.TriggerCallback('v-world:delete', function(res) cb(res or false) end, data)
end)

-- Open a target player's inventory (admin) — closes the panel, then opens the container.
RegisterNUICallback('openinv', function(data, cb)
    local target = tonumber(data and data.target)
    closePanel()
    if target and GetResourceState('v-inventory') == 'started' then
        TriggerServerEvent('v-inventory:server:adminOpenInv', target)
    end
    cb('ok')
end)

-- ══ Admin self-tools (client-side; only usable once the admin panel authorised) ══
noclipOn, godOn, invisOn, espOn = false, false, false, false

-- ── Noclip (free camera-relative flight through the world) ─────
local function setNoclip(on)
    if not amAdmin then return end
    noclipOn = on and true or false
    local ped = PlayerPedId()
    local ent = (IsPedInAnyVehicle(ped, false) and GetVehiclePedIsIn(ped, false)) or ped
    SetEntityInvincible(ent, noclipOn)
    FreezeEntityPosition(ent, noclipOn)
    SetEntityCollision(ent, not noclipOn, not noclipOn)
    if not noclipOn then SetEntityVelocity(ent, 0.0, 0.0, 0.0) end
    Core.Notify((strings()['adm.noclip'] or 'Noclip') .. ': ' .. (noclipOn and 'ON' or 'OFF'), noclipOn and 'success' or 'info')
end

CreateThread(function()
    while true do
        local wait = 500
        if noclipOn then
            wait = 0
            local ped = PlayerPedId()
            local ent = (IsPedInAnyVehicle(ped, false) and GetVehiclePedIsIn(ped, false)) or ped
            local r = GetGameplayCamRot(2)
            local pitch, yaw = math.rad(r.x), math.rad(r.z)
            local cosP = math.cos(pitch)
            local fwd = vector3(-math.sin(yaw) * cosP, math.cos(yaw) * cosP, math.sin(pitch))
            local rgt = vector3(math.cos(yaw), math.sin(yaw), 0.0)
            local speed = 1.0
            if IsDisabledControlPressed(0, 21) then speed = 4.0 end    -- LSHIFT: fast
            if IsDisabledControlPressed(0, 36) then speed = 0.25 end   -- LCTRL: slow
            local move = vector3(0.0, 0.0, 0.0)
            if IsDisabledControlPressed(0, 32) then move = move + fwd end             -- W
            if IsDisabledControlPressed(0, 33) then move = move - fwd end             -- S
            if IsDisabledControlPressed(0, 34) then move = move - rgt end             -- A
            if IsDisabledControlPressed(0, 35) then move = move + rgt end             -- D
            if IsDisabledControlPressed(0, 22) then move = move + vector3(0,0,1.0) end -- SPACE: up
            if IsDisabledControlPressed(0, 44) then move = move - vector3(0,0,1.0) end -- Q: down
            local p = GetEntityCoords(ent)
            local np = p + move * speed
            SetEntityCoordsNoOffset(ent, np.x, np.y, np.z, true, true, true)
            if ent == ped then SetEntityHeading(ped, math.deg(-yaw) % 360.0) end
            DisableControlAction(0, 32, true); DisableControlAction(0, 33, true)
            DisableControlAction(0, 34, true); DisableControlAction(0, 35, true)
        end
        Wait(wait)
    end
end)

RegisterCommand('vadmin_noclip', function() if amAdmin then setNoclip(not noclipOn) end end, false)
RegisterKeyMapping('vadmin_noclip', 'Admin: toggle noclip', 'keyboard', 'F9')

-- ── God mode / invisible ───────────────────────────────────────
local function setGod(on)
    if not amAdmin then return end
    godOn = on and true or false
    SetEntityInvincible(PlayerPedId(), godOn)
    SetPlayerInvincible(PlayerId(), godOn)
end
local function setInvis(on)
    if not amAdmin then return end
    invisOn = on and true or false
    SetEntityVisible(PlayerPedId(), not invisOn, false)
end

-- ── Player ESP: blips + name tags for EVERY online player ──────
local espBlips = {}   -- [serverId] = blip
local function clearEsp()
    for _, b in pairs(espBlips) do if DoesBlipExist(b) then RemoveBlip(b) end end
    espBlips = {}
end
local function setEsp(on)
    if not amAdmin then return end
    espOn = on and true or false
    TriggerServerEvent('v-admin:server:esp', espOn)
    if not espOn then clearEsp() end
end

-- Server streams every player's position while ESP is on.
RegisterNetEvent('v-admin:client:positions', function(list)
    if not espOn then return end
    local seen = {}
    for _, pl in ipairs(list or {}) do
        seen[pl.id] = true
        local b = espBlips[pl.id]
        if not b or not DoesBlipExist(b) then
            b = AddBlipForCoord(pl.x, pl.y, pl.z); espBlips[pl.id] = b
            SetBlipSprite(b, 1); SetBlipScale(b, 0.85); SetBlipColour(b, 3)
            SetBlipCategory(b, 7)
            BeginTextCommandSetBlipName('STRING')
            AddTextComponentSubstringPlayerName(('[%d] %s'):format(pl.id, pl.name or '?'))
            EndTextCommandSetBlipName(b)
        else
            SetBlipCoords(b, pl.x, pl.y, pl.z)
        end
    end
    for id, b in pairs(espBlips) do
        if not seen[id] then if DoesBlipExist(b) then RemoveBlip(b) end; espBlips[id] = nil end
    end
end)

-- ── Spectate a player (free look at their location) ────────────
local spectating = nil
RegisterNetEvent('v-admin:client:spectate', function(x, y, z, target)
    -- teleport onto the target + noclip; re-selecting the SAME target turns it off,
    -- selecting a different player switches to them (instead of toggling off).
    local ped = PlayerPedId()
    if spectating and spectating == target then
        setNoclip(false); spectating = nil
        Core.Notify(strings()['adm.spec_off'] or 'Spectate off.', 'info'); return
    end
    spectating = target or true
    SetEntityCoordsNoOffset(ped, x, y, z + 0.5, false, false, false)
    if not noclipOn then setNoclip(true) end
    Core.Notify(strings()['adm.spec_on'] or 'Spectating — noclip enabled.', 'success')
end)

RegisterNUICallback('tool', function(data, cb)
    if not amAdmin then cb(false); return end
    local k = data and data.tool
    if k == 'noclip' then setNoclip(not noclipOn)
    elseif k == 'god' then setGod(not godOn)
    elseif k == 'invisible' then setInvis(not invisOn)
    elseif k == 'esp' then setEsp(not espOn) end
    cb({ noclip = noclipOn, god = godOn, invisible = invisOn, esp = espOn })
end)

-- ── Effects executed on this client ────────────────────────────
local function doHeal(silent)
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
    if not silent then Core.Notify(strings()['adm.healed'] or 'You have been healed.', 'success') end
end

RegisterNetEvent('v-admin:client:heal', function() doHeal(false) end)

-- Self quick-actions from the panel's Tools tab (admin only).
-- Server revokes the admin tools when this player is demoted below admin. Disable
-- everything WHILE amAdmin is still true (the setters early-return otherwise), then clear.
RegisterNetEvent('v-admin:client:revoke', function()
    setNoclip(false); setGod(false); setInvis(false); setEsp(false)
    amAdmin = false
    if isOpen then closePanel() end
end)

-- Current position readout for the coord-copy tool.
RegisterNUICallback('coords', function(_, cb)
    if not amAdmin then cb(false); return end
    local ped = PlayerPedId()
    local c = GetEntityCoords(ped)
    local h = GetEntityHeading(ped)
    local function r(n) return math.floor(n * 100 + 0.5) / 100 end
    local s1 = GetStreetNameAtCoord(c.x, c.y, c.z)
    local street = (s1 and s1 ~= 0) and GetStreetNameFromHashKey(s1) or ''
    local veh = GetVehiclePedIsIn(ped, false)
    cb({
        v3      = ('vector3(%s, %s, %s)'):format(r(c.x), r(c.y), r(c.z)),
        v4      = ('vector4(%s, %s, %s, %s)'):format(r(c.x), r(c.y), r(c.z), r(h)),
        heading = tostring(r(h)),
        raw     = ('%s, %s, %s'):format(r(c.x), r(c.y), r(c.z)),
        street  = street,
        model   = (veh ~= 0) and GetDisplayNameFromVehicleModel(GetEntityModel(veh)) or '',
    })
end)

-- Clothing thumbnail scan — moved here from a keybind + a chat command so every admin
-- action lives in one permission-gated place. v-clothing re-checks the permission itself.
RegisterNUICallback('scanCats', function(_, cb)
    if not amAdmin then cb(false); return end
    cb(exports['v-clothing']:GetScanCategories() or {})
end)

RegisterNUICallback('scan', function(data, cb)
    if not amAdmin then cb(false); return end
    closePanel()   -- the scan needs a clean screen and its own NUI
    TriggerServerEvent('v-clothing:server:requestScan', (data and data.mode) or 'new', data and data.cat)
    cb(true)
end)

RegisterNUICallback('self', function(data, cb)
    if not amAdmin then cb(false); return end
    local ped = PlayerPedId()
    local a = data and data.act
    if a == 'heal' then doHeal(false)
    elseif a == 'revive' then
        if IsEntityDead(ped) then
            local c = GetEntityCoords(ped)
            NetworkResurrectLocalPlayer(c.x, c.y, c.z, GetEntityHeading(ped), true, false)
        end
        doHeal(true)
        Core.Notify(strings()['adm.revived'] or 'Revived.', 'success')
    elseif a == 'armor' then SetPedArmour(ped, 100); Core.Notify(strings()['adm.armored'] or 'Armor refilled.', 'success')
    else cb(false); return end
    cb(true)
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
    SetNuiFocus(false, false)
    exports['v-core']:MenuClosed()
    -- Restore the ped if any self-tool was left on.
    local ped = PlayerPedId()
    FreezeEntityPosition(ped, false); SetEntityCollision(ped, true, true)
    SetEntityInvincible(ped, false); SetPlayerInvincible(PlayerId(), false)
    SetEntityVisible(ped, true, false)
    for _, b in pairs(espBlips or {}) do if DoesBlipExist(b) then RemoveBlip(b) end end
end)
