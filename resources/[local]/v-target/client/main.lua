-- v-target | client core
-- A universal interaction "eye": hold the key, a FREE CURSOR appears, hover an entity
-- (or stand in a zone) and click an option. Options are filtered by the player's
-- permission, job/grade and any custom predicate. Other resources register options
-- via the exports at the bottom.
local Core = exports['v-core']:GetCore()

-- ── Registries ────────────────────────────────────────────────
local GlobalPlayer, GlobalPed, GlobalVehicle, GlobalObject = {}, {}, {}, {}
local Models   = {}   -- [modelHash] = { option, ... }
local Entities = {}   -- [netId] = { option, ... }
local Zones    = {}   -- [name] = { kind='box'|'sphere', coords, size|radius, options }
local uid = 0
local function nextName() uid = uid + 1; return 'zone_' .. uid end

-- ── Permission / job gating (client-side display filter) ──────
-- The REAL authority still lives in each option's handler (server side); this only
-- decides what to *show*, so a player never sees an action they can't take.
local PERM_ORDER = { user = 1, mod = 2, admin = 3, superadmin = 4 }
local function playerData() return exports['v-core']:GetPlayerData() or {} end

local function hasPerm(needed)
    if not needed then return true end
    local mine = playerData().permission or 'user'
    return (PERM_ORDER[mine] or 1) >= (PERM_ORDER[needed] or 99)
end

local function hasJob(opt)
    if not opt.job then return true end
    local job = playerData().job
    if not job then return false end
    local jobs = (type(opt.job) == 'table') and opt.job or { opt.job }
    for _, j in ipairs(jobs) do
        if job.name == j then return not opt.grade or (job.grade or 0) >= opt.grade end
    end
    return false
end

local function optionAllowed(opt, data)
    if not hasPerm(opt.permission) then return false end
    if not hasJob(opt) then return false end
    if opt.distance and data.distance and data.distance > opt.distance then return false end
    if opt.canInteract then
        local ok, res = pcall(opt.canInteract, data.entity, data.distance, data.coords, data)
        if not ok or res == false then return false end
    end
    return true
end

-- ── Cursor → world ray (perspective projection through the free cursor) ──
local cursorX, cursorY = 0.5, 0.5   -- normalised 0..1, updated by the NUI

local function rotToDir(rx, rz)
    rx, rz = math.rad(rx), math.rad(rz)
    local cx = math.cos(rx)
    return vector3(-math.sin(rz) * cx, math.cos(rz) * cx, math.sin(rx))
end

local function cursorRay()
    local camPos = GetGameplayCamCoord()
    local camRot = GetGameplayCamRot(2)
    local fov    = GetGameplayCamFov()

    local forward = rotToDir(camRot.x, camRot.z)
    local right   = rotToDir(0.0, camRot.z - 90.0)   -- horizontal right
    local up = vector3(                              -- up = right x forward
        right.y * forward.z - right.z * forward.y,
        right.z * forward.x - right.x * forward.z,
        right.x * forward.y - right.y * forward.x)

    local aspect = GetAspectRatio(true)
    local tanV = math.tan(math.rad(fov) * 0.5)
    local ndcX = (cursorX - 0.5) * 2.0
    local ndcY = (cursorY - 0.5) * 2.0
    local dir = forward + right * (ndcX * tanV * aspect) + up * (-ndcY * tanV)
    local len = #(dir)
    if len > 0 then dir = dir / len end
    return camPos, dir
end

local function castEye()
    local camPos, dir = cursorRay()
    local dest = camPos + dir * (Config.MaxDistance or 7.0)
    local ray = StartExpensiveSynchronousShapeTestLosProbe(
        camPos.x, camPos.y, camPos.z, dest.x, dest.y, dest.z, -1, PlayerPedId(), 0)
    local _, hit, endCoords, _, entity = GetShapeTestResult(ray)
    if hit == 1 and entity and entity ~= 0 then return entity, endCoords end
    return nil, endCoords
end

-- ── Option collection ─────────────────────────────────────────
local function appendGroup(dst, group, data)
    if not group then return end
    for _, opt in ipairs(group) do
        if optionAllowed(opt, data) then dst[#dst + 1] = opt end
    end
end

local function collectOptions()
    local ped = PlayerPedId()
    local pcoords = GetEntityCoords(ped)
    local entity, endCoords = castEye()

    local data = { entity = entity, coords = endCoords }
    if entity then
        data.distance = #(pcoords - GetEntityCoords(entity))
        if NetworkGetEntityIsNetworked(entity) then data.netId = NetworkGetNetworkIdFromEntity(entity) end
    end

    local opts = {}
    if entity then
        local etype = GetEntityType(entity)
        if etype == 1 then
            if IsPedAPlayer(entity) then
                data.playerId = NetworkGetPlayerIndexFromPed(entity)
                data.playerServerId = data.playerId and GetPlayerServerId(data.playerId) or nil
                appendGroup(opts, GlobalPlayer, data)
            end
            appendGroup(opts, GlobalPed, data)
        elseif etype == 2 then
            appendGroup(opts, GlobalVehicle, data)
        elseif etype == 3 then
            appendGroup(opts, GlobalObject, data)
        end
        appendGroup(opts, Models[GetEntityModel(entity)], data)
        if data.netId then appendGroup(opts, Entities[data.netId], data) end
    end

    for name, z in pairs(Zones) do
        local inside
        if z.kind == 'sphere' then
            inside = #(pcoords - z.coords) <= (z.radius or 1.5)
        else
            local d = pcoords - z.coords
            inside = math.abs(d.x) <= z.size.x and math.abs(d.y) <= z.size.y and math.abs(d.z) <= z.size.z
        end
        if inside then
            appendGroup(opts, z.options, { zone = name, coords = z.coords, distance = #(pcoords - z.coords) })
        end
    end
    return opts, data, entity
end

-- ── Run a chosen option ───────────────────────────────────────
local function runOption(opt, data)
    if type(opt.action) == 'function' then pcall(opt.action, data)
    elseif opt.event then TriggerEvent(opt.event, data)
    elseif opt.serverEvent then TriggerServerEvent(opt.serverEvent, data.netId or data.playerServerId, data)
    elseif opt.export and opt.export.resource and opt.export.method then
        pcall(function() exports[opt.export.resource][opt.export.method](nil, data) end)
    end
end

-- ── Eye loop ──────────────────────────────────────────────────
local active, current, currentData = false, nil, nil
local highlighted = nil

local function strings()
    return Locales[(LocalPlayer.state and LocalPlayer.state.lang) or 'fr'] or Locales.fr or {}
end

local function clearHighlight()
    if highlighted and DoesEntityExist(highlighted) then SetEntityDrawOutline(highlighted, false) end
    highlighted = nil
end

local function openEye()
    if active or exports['v-core']:IsAnyMenuOpen() then return end
    active = true
    cursorX, cursorY = 0.5, 0.5
    SetNuiFocus(true, true)
    SetNuiFocusKeepInput(false)
    SendNUIMessage({ action = 'eyeon' })
    exports['v-core']:MenuOpened('v-target')

    CreateThread(function()
        SetCursorLocation(0.5, 0.5)
        local lastKey = nil
        while active do
            local opts, data, entity = collectOptions()
            currentData = data
            current = opts

            -- Outline the entity under the cursor.
            if entity ~= highlighted then
                clearHighlight()
                if entity and DoesEntityExist(entity) and #opts > 0 then
                    SetEntityDrawOutlineColor(255, 106, 26, 200)
                    SetEntityDrawOutline(entity, true)
                    highlighted = entity
                end
            elseif entity and #opts == 0 then
                clearHighlight()
            end

            local list = {}
            for i, o in ipairs(opts) do
                list[i] = { n = i, label = (o.label and (strings()[o.label] or o.label)) or 'Action', icon = o.icon or nil }
            end
            local key = tostring(#list)
            for _, o in ipairs(list) do key = key .. '|' .. o.label end
            if key ~= lastKey then lastKey = key; SendNUIMessage({ action = 'options', options = list }) end
            Wait(0)
        end
        clearHighlight()
        SetNuiFocus(false, false)
        exports['v-core']:MenuClosed('v-target')
        SendNUIMessage({ action = 'eyeoff' })
    end)
end

local function closeEye() active = false end

-- NUI relays.
RegisterNUICallback('cursor', function(data, cb)
    if data then cursorX = data.x or cursorX; cursorY = data.y or cursorY end
    cb('ok')
end)
RegisterNUICallback('select', function(data, cb)
    local i = data and tonumber(data.index)
    if active and current and i and current[i] then
        local opt, d = current[i], currentData
        active = false
        runOption(opt, d)
    end
    cb('ok')
end)
RegisterNUICallback('closeeye', function(_, cb) active = false; cb('ok') end)

RegisterCommand('+vtarget', function() openEye() end, false)
RegisterCommand('-vtarget', function() closeEye() end, false)
RegisterKeyMapping('+vtarget', 'Interaction eye (target)', 'keyboard', Config.Key or 'LMENU')

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then
        active = false; clearHighlight()
        SetNuiFocus(false, false); SendNUIMessage({ action = 'eyeoff' })
    end
end)

-- ══ Public API (other resources register options from their client scripts) ══
local function addTo(group, options) for _, o in ipairs(options) do group[#group + 1] = o end end

exports('AddGlobalPlayer',  function(options) addTo(GlobalPlayer, options) end)
exports('AddGlobalPed',     function(options) addTo(GlobalPed, options) end)
exports('AddGlobalVehicle', function(options) addTo(GlobalVehicle, options) end)
exports('AddGlobalObject',  function(options) addTo(GlobalObject, options) end)

exports('AddModel', function(models, options)
    if type(models) ~= 'table' then models = { models } end
    for _, m in ipairs(models) do
        local hash = (type(m) == 'string') and joaat(m) or m
        Models[hash] = Models[hash] or {}
        addTo(Models[hash], options)
    end
end)

exports('AddEntity', function(netId, options)
    Entities[netId] = Entities[netId] or {}
    addTo(Entities[netId], options)
end)

exports('AddBoxZone', function(name, coords, size, options)
    name = name or nextName(); Zones[name] = { kind = 'box', coords = coords, size = size, options = options }; return name
end)
exports('AddSphereZone', function(name, coords, radius, options)
    name = name or nextName(); Zones[name] = { kind = 'sphere', coords = coords, radius = radius, options = options }; return name
end)
exports('RemoveZone', function(name) Zones[name] = nil end)
