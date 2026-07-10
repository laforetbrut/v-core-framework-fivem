-- v-spawn | client flow
-- language selection -> identity -> appearance editor -> create & spawn.
local Core = exports['v-core']:GetCore()

local active = false
local currentLang = 'fr'
local identity = { firstname = '', lastname = '', dob = '2000-01-01', sex = 0 }
local appearance = nil

-- NOTE: we deliberately do NOT hold the screen black before the first spawn.
-- The default spawnmanager waits for IsScreenFadedIn() before firing
-- `playerSpawned` (which starts the whole load chain), so any pre-spawn fade-out
-- deadlocks the spawn -> infinite black screen. The brief flash of the default
-- spawn point is acceptable; each flow (startCreator / onPlayerLoaded) fades out
-- and takes over immediately after.

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

local selectedSlot = 1

-- Put the player in the creator interior (private bucket already set server-side),
-- freeze, give a default ped + orbit camera, and fade in. Shared by the character
-- selection screen and the creation flow.
local function setupScene()
    DoScreenFadeOut(400)
    Wait(450)
    local ped = PlayerPedId()
    local c = Config.CreatorCoords
    SetEntityCoordsNoOffset(ped, c.x, c.y, c.z, false, false, false)
    SetEntityHeading(ped, c.w)
    FreezeEntityPosition(ped, true)
    SetPlayerControl(PlayerId(), false, 0)
    pcall(function()
        SetSexModel(0)
        ApplyAppearance(DefaultAppearance(0))
        CreatorCameraStart()
    end)
    Wait(200)
    DoScreenFadeIn(500)
end

-- On connect: show the character selection screen (slots per permission tier).
RegisterNetEvent('v-core:client:characterSelect', function(info)
    if active then return end
    active = true
    currentLang = (info and info.language) or 'fr'
    setupScene()
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'characters', data = {
        characters = (info and info.characters) or {},
        maxSlots   = (info and info.maxSlots) or 1,
        canDelete  = info and info.canDelete == true,
        strings    = Locales[currentLang] or {},
    } })
end)

-- Returning character: restore the look, then swoop down (GTA switch
-- effect) onto the last saved position instead of the default spawn.
AddEventHandler('v-core:client:onPlayerLoaded', function(data)
    if active then return end
    CreateThread(function()
        DoScreenFadeOut(300); Wait(320)   -- black out before we restyle + switch
        local ped = PlayerPedId()
        FreezeEntityPosition(ped, true)
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

-- ── Character selection callbacks ──
-- Load an existing character. active is cleared FIRST so the incoming
-- playerLoaded -> onPlayerLoaded fires and runs the spawn (it early-returns
-- while `active`). The screen stays black through the switch.
RegisterNUICallback('selectCharacter', function(data, cb)
    cb('ok')
    active = false
    pcall(CreatorCameraStop)
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
    DoScreenFadeOut(0)
    Core.TriggerCallback('v-core:selectCharacter', function(ok)
        if not ok then DoScreenFadeIn(400) end   -- shouldn't happen; don't strand on black
    end, data.citizenid)
end)

-- Create a new character in an empty slot -> straight into the creator.
RegisterNUICallback('createInSlot', function(data, cb)
    cb('ok')
    selectedSlot = tonumber(data.slot) or 1
    identity = { firstname = '', lastname = '', dob = '2000-01-01', sex = 0 }
    appearance = DefaultAppearance(0)
    pcall(function() SetSexModel(0); ApplyAppearance(appearance) end)
    SendNUIMessage({ action = 'strings', strings = Locales[currentLang] or {} })
    SendNUIMessage({ action = 'screen', screen = 'identity' })
end)

-- Delete one of the player's characters (server permission-gated) -> refresh list.
RegisterNUICallback('deleteCharacter', function(data, cb)
    Core.TriggerCallback('v-core:deleteCharacter', function(res)
        if res and res.ok then cb({ characters = res.characters }) else cb(false) end
    end, data.citizenid)
end)

-- ── Creator callbacks ──
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
        slot = selectedSlot,
    })
    cb('ok')
end)

RegisterNUICallback('spawnAt', function(data, cb)
    local pt = Config.SpawnPoints[1]
    for _, p in ipairs(Config.SpawnPoints) do if p.key == data.key then pt = p; break end end
    cb('ok')
    CreateThread(function() finishCreator(pt.coords) end)
end)
