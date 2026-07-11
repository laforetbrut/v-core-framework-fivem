-- v-target | client core
-- A universal interaction "eye": hold the key, look at an entity (or stand in a zone),
-- and pick from options that are filtered by the player's permission, job/grade and any
-- custom predicate. Other resources register options via the exports at the bottom.
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
        if job.name == j then
            return not opt.grade or (job.grade or 0) >= opt.grade
        end
    end
    return false
end

local function optionAllowed(opt, data)
    if not hasPerm(opt.permission) then return false end
    if not hasJob(opt) then return false end
    if opt.canInteract then
        local ok, res = pcall(opt.canInteract, data.entity, data.distance, data.coords, data)
        if not ok or res == false then return false end
    end
    return true
end

-- ── Raycast straight out of the camera (look-to-target) ───────
local function rotationToDirection(rot)
    local z, x = math.rad(rot.z), math.rad(rot.x)
    local num = math.abs(math.cos(x))
    return vector3(-math.sin(z) * num, math.cos(z) * num, math.sin(x))
end

local function castEye()
    local cam = GetGameplayCamCoord()
    local dir = rotationToDirection(GetGameplayCamRot(2))
    local dest = cam + dir * (Config.MaxDistance or 7.0)
    local ray = StartExpensiveSynchronousShapeTestLosProbe(
        cam.x, cam.y, cam.z, dest.x, dest.y, dest.z, -1, PlayerPedId(), 0)
    local _, hit, endCoords, _, entity = GetShapeTestResult(ray)
    if hit == 1 and entity and entity ~= 0 then return entity, endCoords end
    return nil, endCoords
end

-- ── Build the option list for what the eye is on right now ────
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

    -- Zones are location-based (offered whenever you stand inside them).
    for name, z in pairs(Zones) do
        local inside
        if z.kind == 'sphere' then
            inside = #(pcoords - z.coords) <= (z.radius or 1.5)
        else
            local d = pcoords - z.coords
            inside = math.abs(d.x) <= z.size.x and math.abs(d.y) <= z.size.y and math.abs(d.z) <= z.size.z
        end
        if inside then
            local zdata = { zone = name, coords = z.coords, distance = #(pcoords - z.coords) }
            appendGroup(opts, z.options, zdata)
        end
    end
    return opts, data
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

local function strings()
    return Locales[(LocalPlayer.state and LocalPlayer.state.lang) or 'fr'] or Locales.fr or {}
end

local function openEye()
    if active or (exports['v-core']:IsAnyMenuOpen()) then return end
    active = true
    SendNUIMessage({ action = 'eyeon' })
    CreateThread(function()
        local lastKey = nil
        while active do
            local opts, data = collectOptions()
            currentData = data
            -- Serialise a light option list for the NUI (index-keyed).
            local list = {}
            for i, o in ipairs(opts) do
                list[i] = { n = i, label = (o.label and (strings()[o.label] or o.label)) or 'Action', icon = o.icon or nil }
            end
            current = opts
            local key = table.concat((function() local t = {} for _, o in ipairs(list) do t[#t+1] = o.label end return t end)(), '|')
            if key ~= lastKey then lastKey = key; SendNUIMessage({ action = 'options', options = list }) end

            -- Block shooting/aiming and weapon-select keys while the eye is open.
            DisableControlAction(0, 24, true); DisableControlAction(0, 25, true)
            DisableControlAction(0, 257, true); DisableControlAction(0, 1, true); DisableControlAction(0, 2, true)
            for i = 1, 9 do DisableControlAction(0, 156 + i, true) end          -- number row 1..9

            -- Selection: number keys 1..N, or left mouse = option 1.
            if #opts > 0 then
                local pick
                if IsDisabledControlJustPressed(0, 24) then pick = 1 end        -- LMB
                for i = 1, math.min(#opts, 9) do
                    if IsDisabledControlJustPressed(0, 156 + i) then pick = i end -- keys 1..9
                end
                if pick and opts[pick] then
                    active = false
                    runOption(opts[pick], currentData)
                    break
                end
            end
            Wait(0)
        end
        active = false
        SendNUIMessage({ action = 'eyeoff' })
    end)
end

local function closeEye()
    active = false
end

RegisterCommand('+vtarget', function() openEye() end, false)
RegisterCommand('-vtarget', function() closeEye() end, false)
RegisterKeyMapping('+vtarget', 'Interaction eye (target)', 'keyboard', Config.Key or 'LMENU')

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then active = false; SendNUIMessage({ action = 'eyeoff' }) end
end)

-- ══ Public API (other resources register options from their client scripts) ══
-- Each `options` is a list of option tables. Option fields:
--   label (i18n key or text), icon, distance, permission, job (name|list), grade,
--   canInteract(entity, distance, coords, data)->bool, and ONE of:
--   action(data) | event | serverEvent | export = { resource, method }.
local function addTo(group, options)
    for _, o in ipairs(options) do group[#group + 1] = o end
end

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
    name = name or nextName()
    Zones[name] = { kind = 'box', coords = coords, size = size, options = options }
    return name
end)

exports('AddSphereZone', function(name, coords, radius, options)
    name = name or nextName()
    Zones[name] = { kind = 'sphere', coords = coords, radius = radius, options = options }
    return name
end)

exports('RemoveZone', function(name) Zones[name] = nil end)
