-- v-music | client
-- Plays what the server says is playing, at the volume this client's own distance earns.
--
-- The difference from `v-3dsound`: a one-shot fires and forgets, but music is continuous,
-- so the volume has to track the listener as they walk. That loop is the module.

local Sources = {}          -- [id] = source row from the server
local Jukeboxes = {}
local outsideMult = 0.45
local props = {}            -- [id] = local boombox entity
local open = false

local function strings()
    return Locales[(LocalPlayer.state and LocalPlayer.state.lang) or 'fr'] or Locales.fr or {}
end
local function L(k) return strings()[k] or k end
local function num(v, d) return tonumber(v) or d or 0 end

--- Same curve as v-3dsound: linear with a flat head. Full volume up close, silent at the
--- edge, and nothing past half the range disappearing the way a squared curve would.
local function attenuate(dist, range)
    if range <= 0 then return 0.0 end
    local near = range * 0.15
    if dist <= near then return 1.0 end
    if dist >= range then return 0.0 end
    return 1.0 - ((dist - near) / (range - near))
end

local function positionOf(s)
    if s.netid then
        local ent = NetToVeh(s.netid)
        if ent and ent ~= 0 and DoesEntityExist(ent) then return GetEntityCoords(ent), ent end
    end
    -- A phone walks around with the person holding it.
    if s.player then
        local pl = GetPlayerFromServerId(s.player)
        if pl and pl ~= -1 then
            local ped = GetPlayerPed(pl)
            if ped and ped ~= 0 and DoesEntityExist(ped) then return GetEntityCoords(ped), ped end
        end
        return vector3(0.0, 0.0, 0.0), nil
    end
    return vector3(num(s.x), num(s.y), num(s.z)), nil
end

-- ── Props ──────────────────────────────────────────────────────
-- Local and non-networked, for the same reason as the drug plants: a boombox is server
-- state, and a networked entity would let any client delete somebody else's.
local function syncProps()
    local me = GetEntityCoords(PlayerPedId())
    for id, s in pairs(Sources) do
        if s.kind == 'boombox' then
            local pos = vector3(num(s.x), num(s.y), num(s.z))
            local near = #(me - pos) < 90.0
            if near and not props[id] then
                local model = joaat(Config.Boombox.prop)
                RequestModel(model)
                local t = 0
                while not HasModelLoaded(model) and t < 60 do Wait(10); t = t + 1 end
                if HasModelLoaded(model) then
                    local ent = CreateObject(model, pos.x, pos.y, pos.z, false, false, false)
                    PlaceObjectOnGroundProperly(ent)
                    FreezeEntityPosition(ent, true)
                    props[id] = ent
                end
            elseif not near and props[id] then
                if DoesEntityExist(props[id]) then DeleteEntity(props[id]) end
                props[id] = nil
            end
        end
    end
    for id, ent in pairs(props) do
        if not Sources[id] then
            if DoesEntityExist(ent) then DeleteEntity(ent) end
            props[id] = nil
        end
    end
end

-- ── Playback ───────────────────────────────────────────────────
RegisterNetEvent('v-music:client:sources', function(list, outside)
    local prev = Sources
    Sources = list or {}
    outsideMult = num(outside, 0.45)

    -- Start what is new, stop what is gone, and re-seek anything whose start time moved
    -- (a pause and resume changes it).
    for id, s in pairs(Sources) do
        local was = prev[id]
        if not was or was.url ~= s.url or was.startedAt ~= s.startedAt or was.paused ~= s.paused then
            SendNUIMessage({ action = 'source', id = id, url = s.url,
                             offset = math.max(0, os.time() - num(s.startedAt)),
                             paused = s.paused == true })
        end
    end
    for id in pairs(prev) do
        if not Sources[id] then SendNUIMessage({ action = 'stop', id = id }) end
    end
    syncProps()
end)

RegisterNetEvent('v-music:client:jukeboxes', function(list) Jukeboxes = list or {} end)

-- The volume loop. 250 ms is well below what an ear notices as a step and well above what
-- a per-frame loop would cost for something that only changes as fast as a person walks.
CreateThread(function()
    while true do
        Wait(250)
        if next(Sources) then
            local ped = PlayerPedId()
            local me = GetEntityCoords(ped)
            local myVeh = GetVehiclePedIsIn(ped, false)
            local myId = GetPlayerServerId(PlayerId())
            for id, s in pairs(Sources) do
                local pos, ent = positionOf(s)
                local vol
                if s.private then
                    -- Somebody's headphones. Silent for everyone except the ear it
                    -- belongs to, and at full volume there, because distance from
                    -- yourself is not a thing.
                    vol = (s.private == myId) and num(s.volume, 0.6) or 0.0
                else
                    vol = attenuate(#(me - pos), num(s.range, 25.0)) * num(s.volume, 0.6)
                end
                -- Sitting in the car it belongs to is the loud seat; everyone else hears
                -- it through the bodywork.
                if s.kind == 'vehicle' and ent and myVeh ~= ent then
                    vol = vol * outsideMult
                end
                SendNUIMessage({ action = 'volume', id = id, volume = vol })
            end
        end
    end
end)

CreateThread(function()
    while true do
        Wait(5000)
        syncProps()
    end
end)

-- ── Panel ──────────────────────────────────────────────────────
local function close()
    if not open then return end
    open = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
    if GetResourceState('v-core') == 'started' then
        pcall(function() exports['v-core']:MenuClosed('v-music') end)
    end
end

local function openPanel(kind, id)
    V.Request('v-music:list', function(res)
        if not res or res.error then return end
        if res.enabled == false then V.Notify(L('mus.err_off'), 'error') return end
        open = true
        SetNuiFocus(true, true)
        if GetResourceState('v-core') == 'started' then
            pcall(function() exports['v-core']:MenuOpened('v-music') end)
        end
        SendNUIMessage({ action = 'open', data = res, kind = kind, target = id,
                         strings = strings() })
    end)
end

RegisterNetEvent('v-music:client:open', function(kind) if not open then openPanel(kind) end end)

-- In a vehicle the key controls the stereo; on foot it reaches a jukebox you are standing
-- at. One key, context-dependent, rather than two the player has to remember.
RegisterCommand('vmusic', function()
    if open then close() return end
    local ped = PlayerPedId()
    if IsPedInAnyVehicle(ped, false) then openPanel('vehicle') return end
    local me = GetEntityCoords(ped)
    for id, j in pairs(Jukeboxes) do
        if #(me - vector3(j.x + 0.0, j.y + 0.0, j.z + 0.0)) <= Config.Distance + 1.5 then
            openPanel('jukebox', id) return
        end
    end
    openPanel('boombox')
end, false)
RegisterKeyMapping('vmusic', 'Music: boombox / stereo / jukebox', 'keyboard', Config.Key or 'F4')

RegisterNUICallback('close', function(_, cb) close(); cb('ok') end)

RegisterNUICallback('play', function(d, cb)
    cb('ok')
    V.Request('v-music:play', function(res)
        if res and res.ok then V.Notify(L('mus.playing'), 'success')
        else V.Notify(L('mus.err_' .. ((res and res.error) or 'x')), 'error') end
    end, { kind = d.kind, id = d.id, url = d.url, title = d.title, volume = d.volume })
end)

RegisterNUICallback('control', function(d, cb)
    cb('ok')
    V.Request('v-music:control', function(res)
        if not (res and res.ok) then
            V.Notify(L('mus.err_' .. ((res and res.error) or 'x')), 'error')
        end
    end, { id = d.id, action = d.action, volume = d.volume })
end)

-- ── Boot ───────────────────────────────────────────────────────
V.Ready(function()
    Wait(2000)
    TriggerServerEvent('v-music:server:request')
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for _, ent in pairs(props) do if DoesEntityExist(ent) then DeleteEntity(ent) end end
    SendNUIMessage({ action = 'stopAll' })
    if open then SetNuiFocus(false, false) end
end)

local function pushTheme()
    if GetResourceState('v-ui') ~= 'started' then return end
    pcall(function() exports['v-ui']:Push() end)
end
AddEventHandler('v-ui:client:themeChanged', function() pushTheme() end)
CreateThread(function() Wait(4000); pushTheme() end)

exports('GetSources', function() return Sources end)
