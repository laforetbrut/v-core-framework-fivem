-- v-spawn | client flow
-- language selection -> identity -> appearance editor -> create & spawn.
local Core = exports['v-core']:GetCore()

local active = false
local currentLang = 'fr'
local identity = { firstname = '', lastname = '', dob = '2000-01-01', sex = 0 }
local appearance = nil

-- Hold the screen black from the very first frame so the default spawnmanager
-- autospawn (a nude freemode ped, often above the void) is NEVER visible. Each
-- flow (creator / switchSpawn) sets spawnReady = true and then owns the fade.
local spawnReady = false
CreateThread(function()
    while not spawnReady do
        if not IsScreenFadedOut() and not IsScreenFadingOut() then DoScreenFadeOut(0) end
        local ped = PlayerPedId()
        if ped and ped ~= 0 then FreezeEntityPosition(ped, true) end
        Wait(0)
    end
end)

-- Stream collision at the target while holding the ped there, then resolve a
-- solid ground Z (retried — the area may still be streaming). Returns ground Z
-- or nil. The ped stays FROZEN throughout, so it can never fall into the void.
local function streamGround(ped, x, y, z)
    for _ = 1, 120 do
        RequestCollisionAtCoord(x, y, z)
        SetEntityCoordsNoOffset(ped, x, y, z, false, false, false)
        if HasCollisionLoadedAroundEntity(ped) then break end
        Wait(50)
    end
    for _ = 1, 25 do
        local ok, gz = GetGroundZFor_3dCoord(x, y, z + 3.0, false)
        if ok and gz and gz > -190.0 and gz ~= 0.0 then return gz end
        Wait(50)
    end
    return nil
end

-- ── GTA-style "switch" spawn (camera swoops down from the sky) ──
-- The ped is frozen at the destination, held in place while collision streams
-- and the ground is found, and only unfrozen AFTER the switch-in completes.
local function switchSpawn(x, y, z, h)
    local ped = PlayerPedId()
    FreezeEntityPosition(ped, true)
    SetEntityCoordsNoOffset(ped, x, y, z, false, false, false)
    SetEntityHeading(ped, h or 0.0)

    local switched = false
    if not IsPlayerSwitchInProgress() then
        pcall(function() SwitchOutPlayer(ped, 0, 1) end)
        local t = 0
        while GetPlayerSwitchState() ~= 5 and t < 200 do Wait(25); t = t + 1 end   -- 5 = up in the clouds
        switched = (GetPlayerSwitchState() == 5)
    end
    if not switched and not IsScreenFadedOut() then DoScreenFadeOut(300); Wait(350) end

    -- ground the ped (frozen) while it is up in the clouds / behind black
    local gz = streamGround(ped, x, y, z)
    SetEntityCoordsNoOffset(ped, x, y, gz and (gz + 1.0) or z, false, false, false)
    SetEntityHeading(ped, h or 0.0)

    if switched then
        pcall(function() SwitchInPlayer(PlayerPedId()) end)
        local t2 = 0
        while GetPlayerSwitchState() ~= 12 and t2 < 300 do Wait(25); t2 = t2 + 1 end   -- 12 = switch complete
    end

    ped = PlayerPedId()
    FreezeEntityPosition(ped, false)   -- unfreeze only now: grounded + switched in
    SetPlayerControl(PlayerId(), true, 0)
    ClearPedTasksImmediately(ped)
    if not IsScreenFadedIn() then DoScreenFadeIn(500) end
end

local function finishCreator(coords)
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
    CreatorCameraStop()
    DoScreenFadeOut(300)
    Wait(350)
    -- stay black; switchSpawn does the swoop and fades in when grounded
    local s = coords or Config.Spawn
    switchSpawn(s.x, s.y, s.z, s.w)
    active = false
end

local function startCreator()
    active = true
    spawnReady = true   -- release the black-out guard; the creator owns the fade now
    identity = { firstname = '', lastname = '', dob = '2000-01-01', sex = 0 }
    appearance = DefaultAppearance(0)

    DoScreenFadeOut(400)
    Wait(450)

    local ped = PlayerPedId()
    local c = Config.CreatorCoords
    SetEntityCoordsNoOffset(ped, c.x, c.y, c.z, false, false, false)
    SetEntityHeading(ped, c.w)
    FreezeEntityPosition(ped, true)
    SetPlayerControl(PlayerId(), false, 0)

    -- Guard the ped/model/camera setup so a native failure can never leave a black screen.
    pcall(function()
        SetSexModel(0)
        ApplyAppearance(appearance)
        CreatorCameraStart()
    end)

    Wait(200)
    DoScreenFadeIn(500)

    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'open' })
end

RegisterNetEvent('v-core:client:needCharacter', function(info)
    if active then return end
    currentLang = (info and info.language) or 'fr'
    startCreator()
end)

-- Returning character: restore the look, then swoop down (GTA switch
-- effect) onto the last saved position instead of the default spawn.
AddEventHandler('v-core:client:onPlayerLoaded', function(data)
    if active then return end
    CreateThread(function()
        spawnReady = true              -- take over the black-out guard
        if not IsScreenFadedOut() then DoScreenFadeOut(0) end
        local ped = PlayerPedId()
        FreezeEntityPosition(ped, true)
        Wait(300)
        -- dress the ped WHILE the screen is black, so the default look is never seen
        if data.appearance and next(data.appearance) then
            if data.appearance.sex then SetSexModel(data.appearance.sex); Wait(250) end
            ApplyAppearance(data.appearance)
            Wait(150)
        end
        local pos = data.position
        if pos and pos.x and pos.y and pos.z then
            switchSpawn(pos.x + 0.0, pos.y + 0.0, pos.z + 0.5, (pos.h or 0.0) + 0.0)
        else
            local s = Config.Spawn
            switchSpawn(s.x, s.y, s.z, s.w)
        end
    end)
end)

-- ── NUI callbacks ──
RegisterNUICallback('selectLang', function(data, cb)
    currentLang = (data.lang == 'en') and 'en' or 'fr'
    Core.TriggerCallback('v-core:setLanguage', function() end, currentLang)
    SendNUIMessage({ action = 'strings', strings = Locales[currentLang] or {} })
    SendNUIMessage({ action = 'screen', screen = 'identity' })
    cb('ok')
end)

RegisterNUICallback('setSex', function(data, cb)
    local sex = tonumber(data.sex) or 0
    identity.sex = sex
    appearance = DefaultAppearance(sex)
    SetSexModel(sex)
    ApplyAppearance(appearance)
    SendNUIMessage({ action = 'appearance', data = appearance })
    cb('ok')
end)

RegisterNUICallback('identityNext', function(data, cb)
    identity.firstname = tostring(data.firstname or ''):sub(1, 24)
    identity.lastname  = tostring(data.lastname or ''):sub(1, 24)
    identity.dob       = tostring(data.dob or '2000-01-01')
    SendNUIMessage({ action = 'screen', screen = 'appearance', appearance = appearance })
    cb('ok')
end)

RegisterNUICallback('updateAppearance', function(data, cb)
    appearance = data.appearance or appearance
    ApplyAppearance(appearance)
    cb('ok')
end)

RegisterNUICallback('camera', function(data, cb)
    if data.orbit then CreatorCameraOrbit(data.orbit.dx, data.orbit.dy) end
    if data.zoom then CreatorCameraZoom(data.zoom) end
    if data.zone then CreatorCameraZone(data.zone) end
    cb('ok')
end)

-- ── Clothing thumbnails (generated by the v-clothing admin scan) ──
-- The creator shows the same garment-only images as the store catalogue.
RegisterNUICallback('clothThumbIndex', function(data, cb)
    if GetResourceState('v-clothing') ~= 'started' then cb({}); return end
    Core.TriggerCallback('v-clothing:thumbIndex', function(list) cb(list or {}) end, data.category)
end)

RegisterNUICallback('clothThumbs', function(data, cb)
    if GetResourceState('v-clothing') ~= 'started' then cb({}); return end
    Core.TriggerCallback('v-clothing:thumbs', function(out) cb(out or {}) end, data.list)
end)

RegisterNUICallback('confirm', function(data, cb)
    if data.appearance then appearance = data.appearance end
    Core.TriggerCallback('v-core:createCharacter', function(ok)
        if ok then
            -- character saved -> let the player pick where their story begins
            local L = Locales[currentLang] or {}
            local spawns = {}
            for _, p in ipairs(Config.SpawnPoints) do
                spawns[#spawns + 1] = { key = p.key, label = L[p.i18n] or p.key, sub = L[p.sub] or '' }
            end
            SendNUIMessage({ action = 'screen', screen = 'spawnselect', spawns = spawns })
        end
    end, {
        firstname = identity.firstname, lastname = identity.lastname,
        dob = identity.dob, sex = identity.sex, appearance = appearance,
    })
    cb('ok')
end)

RegisterNUICallback('spawnAt', function(data, cb)
    local pt = Config.SpawnPoints[1]
    for _, p in ipairs(Config.SpawnPoints) do if p.key == data.key then pt = p; break end end
    cb('ok')
    CreateThread(function() finishCreator(pt.coords) end)
end)
