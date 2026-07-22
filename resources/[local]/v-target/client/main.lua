-- v-target | client core
--
-- The interaction eye. Hold the key, look at something, pick an action.
--
-- Three things about this file are deliberate and have all been got wrong before:
--
--  1. **The ray is asynchronous.** The native called every frame used to be
--     StartExpensiveSynchronousShapeTestLosProbe -- the name is the warning. It blocks
--     the game thread until the physics query answers, sixty times a second. It is now
--     StartShapeTestLosProbe, fired once and read on a later frame; the eye never stalls
--     a frame again.
--
--  2. **The ray comes from the screen centre, not the mouse cursor.** Casting from a free
--     cursor is why the old code needed a sticky-target lock, a panel-hover freeze and a
--     "do not re-acquire" rule stacked on top of each other: moving the cursor onto the
--     options made the ray miss, and the options vanished before they could be clicked.
--     A centre ray cannot miss because you moved the mouse, so all three hacks are gone.
--
--  3. **The cursor position is no longer round-tripped through the NUI.** It used to be
--     posted at most every 50 ms and fed into the raycast, so the outline lagged the
--     visible cursor by up to three frames. That lag WAS the "not fluid" feeling.
--
-- Movement stays under the player's control while the eye is open (see DISABLED below):
-- only look and attack are suppressed, so walking up to a car while choosing what to do
-- with it works the way it should.

-- ── Registries ────────────────────────────────────────────────
local GlobalPlayer, GlobalPed, GlobalVehicle, GlobalObject = {}, {}, {}, {}
local GlobalSelf = {}          -- shown when the eye is pointed at nothing targetable
local Models   = {}            -- [modelHash] = { option, ... }
local Entities = {}            -- [netId]     = { option, ... }
local Zones    = {}            -- [name]      = { kind, ... , options }
local uid, seq = 0, 0
local function nextName() uid = uid + 1; return 'zone_' .. uid end

local function strings()
    return Locales[(LocalPlayer.state and LocalPlayer.state.lang) or 'fr'] or Locales.fr or {}
end
local function L(k) return (k and strings()[k]) or k end

local function setting(key, fallback) return V.Setting(key, fallback) end

-- ══════════════════════════════════════════════════════════════
-- Gating
-- ══════════════════════════════════════════════════════════════
-- Everything here decides what to SHOW. The real authority is always the option's own
-- handler on the server: a client that lies about its job still gets refused there.

local PERM_ORDER = { user = 1, mod = 2, admin = 3, superadmin = 4 }
local function playerData() return exports['v-core']:GetPlayerData() or {} end

local function hasPerm(needed)
    if not needed then return true end
    local mine = playerData().permission or 'user'
    return (PERM_ORDER[mine] or 1) >= (PERM_ORDER[needed] or 99)
end

--- `job` accepts a name, a list of names, or a { name = minGrade } map. The map form is
--- what lets one option say "sergeant and up" without a second option for every rank.
local function hasJob(opt)
    if not opt.job and not opt.groups then return true end
    local want = opt.groups or opt.job
    local job = playerData().job
    if not job or not job.name then return false end

    if type(want) == 'string' then
        return job.name == want and (job.grade or 0) >= (opt.grade or 0)
    end
    if type(want) == 'table' then
        for name, minGrade in pairs(want) do
            if type(name) == 'string' then
                -- map form: { police = 2, sheriff = 0 }
                if job.name == name and (job.grade or 0) >= (tonumber(minGrade) or 0) then return true end
            else
                -- list form: { 'police', 'sheriff' }
                if job.name == minGrade and (job.grade or 0) >= (opt.grade or 0) then return true end
            end
        end
    end
    return false
end

local function hasGang(opt)
    if not opt.gang then return true end
    local gang = playerData().gang
    if not gang or not gang.name then return false end
    local want = (type(opt.gang) == 'table') and opt.gang or { opt.gang }
    for _, g in ipairs(want) do
        if gang.name == g then return (gang.grade or 0) >= (opt.gangGrade or 0) end
    end
    return false
end

--- Duty is only enforced when the framework actually tracks it. A missing `onDuty` means
--- the server does not model duty, and hiding every job option in that case would break
--- the menu rather than gate it.
local function onDuty(opt)
    if not opt.duty then return true end
    local job = playerData().job
    return not (job and job.onDuty == false)
end

--- Carried items, read straight off the player's own statebag (published by v-inventory).
--- Synchronous, so an option can be shown or hidden in the same frame the list is drawn --
--- a callback here would make rows appear a frame late, which reads as flicker.
local function carried()
    return (LocalPlayer.state and LocalPlayer.state.items) or nil
end

local function hasItems(opt)
    local want = opt.items or opt.item
    if not want then return true end
    local have = carried()
    if not have then return false end

    if type(want) == 'string' then return (have[want] or 0) > 0 end
    if want.any then
        for _, n in ipairs(want.any) do if (have[n] or 0) > 0 then return true end end
        return false
    end
    for k, v in pairs(want) do
        if type(k) == 'number' then                       -- { 'lockpick', 'screwdriver' } = ALL of them
            if (have[v] or 0) <= 0 then return false end
        else                                              -- { lockpick = 2 }
            if (have[k] or 0) < (tonumber(v) or 1) then return false end
        end
    end
    return true
end

local function boneAllowed(opt, data)
    local want = opt.bones or opt.bone
    if not want then return true end
    if not data.bone then return false end
    if type(want) == 'string' then return data.bone == want end
    for _, b in ipairs(want) do if data.bone == b then return true end end
    return false
end

local function classAllowed(opt, data)
    if not opt.vehicleClass then return true end
    if not (data.entity and GetEntityType(data.entity) == 2) then return false end
    local class = GetVehicleClass(data.entity)
    local want = (type(opt.vehicleClass) == 'table') and opt.vehicleClass or { opt.vehicleClass }
    for _, c in ipairs(want) do if class == c then return true end end
    return false
end

--- Returns visible, blockedReason.
---   visible = false          -> the row is not drawn at all (job, permission, distance...)
---   visible = true, reason   -> the row is drawn greyed out with that reason
---
--- The split matters: a civilian must not learn what the police menu contains, but a
--- player who is simply too far from a door, or missing the tool, deserves to be told.
local function optionAllowed(opt, data)
    if not hasPerm(opt.permission) then return false end
    if not hasJob(opt) then return false end
    if not hasGang(opt) then return false end
    if not onDuty(opt) then return false end
    if not boneAllowed(opt, data) then return false end
    if not classAllowed(opt, data) then return false end
    if opt.distance and data.distance and data.distance > opt.distance then return false end

    if not hasItems(opt) then
        if not setting('showBlocked', Config.ShowBlocked) then return false end
        return true, 'tgt.need_item'
    end

    if opt.canInteract then
        local ok, res, reason = pcall(opt.canInteract, data.entity, data.distance, data.coords, data)
        if not ok then return false end
        if res == false then
            if reason and setting('showBlocked', Config.ShowBlocked) then return true, reason end
            return false
        end
    end
    return true
end

-- ══════════════════════════════════════════════════════════════
-- The ray
-- ══════════════════════════════════════════════════════════════
local rayHandle = nil
local hitEntity, hitCoords = nil, nil

local function camForward()
    local r = GetGameplayCamRot(2)
    local rx, rz = math.rad(r.x), math.rad(r.z)
    local cx = math.cos(rx)
    return vector3(-math.sin(rz) * cx, math.cos(rz) * cx, math.sin(rx))
end

--- Fire-and-forget. One probe is in flight at a time; its result is read whenever the
--- physics thread has it, and a fresh one is started in the same pass. There is no frame
--- in which the game waits for us.
local function stepRay()
    if rayHandle then
        local state, hit, coords, _, entity = GetShapeTestResult(rayHandle)
        if state ~= 1 then                                -- 1 = still in flight
            rayHandle = nil
            if hit == 1 and entity and entity ~= 0 and DoesEntityExist(entity) then
                hitEntity, hitCoords = entity, coords
            else
                hitEntity, hitCoords = nil, coords
            end
        end
    end
    if not rayHandle then
        local ped    = PlayerPedId()
        local camPos = GetGameplayCamCoord()
        local reach  = tonumber(setting('maxDistance', Config.MaxDistance)) or Config.MaxDistance
        local dest   = camPos + camForward() * reach
        rayHandle = StartShapeTestLosProbe(
            camPos.x, camPos.y, camPos.z, dest.x, dest.y, dest.z,
            Config.RayFlags, ped, 4)
    end
end

-- ── Bones ─────────────────────────────────────────────────────
local function nearestBone(entity, coords, list)
    if not coords then return nil end
    local best = nil
    local bestD = tonumber(setting('boneDistance', Config.BoneDistance)) or Config.BoneDistance
    for _, name in ipairs(list) do
        local idx = GetEntityBoneIndexByName(entity, name)
        if idx ~= -1 then
            local d = #(coords - GetWorldPositionOfEntityBone(entity, idx))
            if d < bestD then best, bestD = name, d end
        end
    end
    return best
end

-- ══════════════════════════════════════════════════════════════
-- Zones
-- ══════════════════════════════════════════════════════════════
local function inBox(z, p)
    local d = p - z.coords
    local h = z.heading or 0.0
    if h ~= 0.0 then
        local r = -math.rad(h)
        local cs, sn = math.cos(r), math.sin(r)
        d = vector3(d.x * cs - d.y * sn, d.x * sn + d.y * cs, d.z)
    end
    local s = z.size
    return math.abs(d.x) <= s.x and math.abs(d.y) <= s.y and math.abs(d.z) <= s.z
end

--- Even-odd ray crossing on XY, with a flat height band. Enough for the shapes a map
--- actually needs (a warehouse floor, a car park, a stretch of beach) and it costs a
--- handful of comparisons per point.
local function inPoly(z, p)
    if math.abs(p.z - z.z) > (z.height or 3.0) then return false end
    local pts = z.points
    local n, j, inside = #pts, #pts, false
    for i = 1, n do
        local a, b = pts[i], pts[j]
        if ((a.y > p.y) ~= (b.y > p.y))
           and (p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x) then
            inside = not inside
        end
        j = i
    end
    return inside
end

local function zoneCentre(z)
    if z.kind == 'poly' then
        local sx, sy = 0.0, 0.0
        for _, pt in ipairs(z.points) do sx, sy = sx + pt.x, sy + pt.y end
        local n = #z.points
        return vector3(sx / n, sy / n, z.z)
    end
    return z.coords
end

local function inZone(z, p)
    if z.kind == 'sphere' then return #(p - z.coords) <= (z.radius or 1.5) end
    if z.kind == 'poly'   then return inPoly(z, p) end
    return inBox(z, p)
end

-- ══════════════════════════════════════════════════════════════
-- Collection
-- ══════════════════════════════════════════════════════════════
-- Each option is paired with the exact data blob it was filtered against, so a zone option
-- runs with { zone, coords, distance } and never with the entity blob it was listed beside.
local function appendGroup(dst, group, data)
    if not group then return end
    for _, opt in ipairs(group) do
        local ok, reason = optionAllowed(opt, data)
        if ok then dst[#dst + 1] = { opt = opt, data = data, blocked = reason } end
    end
end

local function entityLabel(entity, data)
    if not entity then return nil end
    local t = GetEntityType(entity)
    if t == 1 then
        if data.playerServerId then return GetPlayerName(data.playerId) or L('tgt.lbl_player') end
        return L('tgt.lbl_ped')
    elseif t == 2 then
        local name = GetLabelText(GetDisplayNameFromVehicleModel(GetEntityModel(entity)))
        if name == 'NULL' then name = L('tgt.lbl_vehicle') end
        local plate = GetVehicleNumberPlateText(entity)
        if plate then plate = plate:gsub('%s+$', '') end
        return (plate and plate ~= '') and (name .. '  ' .. plate) or name
    end
    return L('tgt.lbl_object')
end

--- Returns entries, title.
local function collect()
    local ped     = PlayerPedId()
    local pcoords = GetEntityCoords(ped)
    local entity  = hitEntity
    local entries = {}

    local data = { entity = entity, coords = hitCoords }
    if entity then
        data.distance = #(pcoords - GetEntityCoords(entity))
        data.model    = GetEntityModel(entity)
        if NetworkGetEntityIsNetworked(entity) then
            data.netId = NetworkGetNetworkIdFromEntity(entity)
        end

        local etype = GetEntityType(entity)
        data.type = etype
        if etype == 1 then
            data.bone = nearestBone(entity, hitCoords, Config.PedBones)
            if IsPedAPlayer(entity) then
                data.playerId       = NetworkGetPlayerIndexFromPed(entity)
                data.playerServerId = data.playerId and GetPlayerServerId(data.playerId) or nil
                appendGroup(entries, GlobalPlayer, data)
            end
            appendGroup(entries, GlobalPed, data)
        elseif etype == 2 then
            data.bone = nearestBone(entity, hitCoords, Config.VehicleBones)
            appendGroup(entries, GlobalVehicle, data)
        elseif etype == 3 then
            appendGroup(entries, GlobalObject, data)
        end
        appendGroup(entries, Models[data.model], data)
        if data.netId then appendGroup(entries, Entities[data.netId], data) end
    end

    local zoneTitle
    for name, z in pairs(Zones) do
        if inZone(z, pcoords) then
            local centre = zoneCentre(z)
            appendGroup(entries, z.options, {
                zone = name, zoneLabel = z.label, coords = centre,
                distance = #(pcoords - centre),
            })
            zoneTitle = zoneTitle or z.label
        end
    end

    -- Nothing to do with the world: offer the player themselves. This is what turns the
    -- eye from a context menu into the main interaction surface -- it is never empty.
    local selfMenu = false
    if #entries == 0 and setting('selfMenu', Config.SelfMenu) then
        appendGroup(entries, GlobalSelf, { self = true, entity = ped, coords = pcoords, distance = 0.0 })
        selfMenu = #entries > 0
    end

    -- Stable ordering: priority first, insertion order second. Without the tiebreak two
    -- equal priorities can swap places between frames and the list visibly jitters.
    for i, e in ipairs(entries) do e.seq = i end
    table.sort(entries, function(a, b)
        local pa, pb = a.opt.priority or 50, b.opt.priority or 50
        if pa ~= pb then return pa < pb end
        return a.seq < b.seq
    end)

    if selfMenu then return entries, L('tgt.self'), true end
    return entries, (entity and entityLabel(entity, data)) or zoneTitle, false
end

-- ══════════════════════════════════════════════════════════════
-- Running an option
-- ══════════════════════════════════════════════════════════════
local active = false
local stopEye                                        -- forward declaration; assigned below
local Stack = {}                                     -- submenu frames, root is Stack[1]

local function runOption(opt, data)
    if type(opt.action) == 'function' then pcall(opt.action, data)
    elseif opt.event then TriggerEvent(opt.event, data)
    elseif opt.serverEvent then TriggerServerEvent(opt.serverEvent, data.netId or data.playerServerId, data)
    elseif opt.export and opt.export.resource and opt.export.method then
        pcall(function() exports[opt.export.resource][opt.export.method](nil, data) end)
    end
end

--- Build the payload the page draws. Kept separate from collect() because a submenu frame
--- is drawn from a frozen entry list that collect() must not touch.
local function payload(frame)
    local list = {}
    for i, e in ipairs(frame.entries) do
        local opt = e.opt
        list[i] = {
            n       = i,
            label   = L(opt.label) or L('tgt.action'),
            icon    = opt.icon,
            hint    = opt.hint and L(opt.hint) or nil,
            blocked = e.blocked and L(e.blocked) or nil,
            sub     = (opt.menu ~= nil) or nil,
        }
    end
    return { action = 'options', options = list, title = frame.title,
             depth = #Stack, ['self'] = frame.isSelf or nil }
end

local function pushMenu(entry)
    local opt  = entry.opt
    local menu = opt.menu
    if type(menu) == 'function' then
        local ok, res = pcall(menu, entry.data)
        menu = ok and res or nil
    end
    if type(menu) ~= 'table' then return false end

    local entries = {}
    appendGroup(entries, menu, entry.data)
    if #entries == 0 then return false end

    Stack[#Stack + 1] = { entries = entries, title = L(opt.label) }
    SendNUIMessage(payload(Stack[#Stack]))
    return true
end

--- One place decides what selecting a row does, because there are three outcomes and
--- getting the order wrong is how the eye used to close on a row that did nothing.
local function chooseRow(index)
    local frame = Stack[#Stack]
    if not frame then return end
    local entry = frame.entries[index]
    if not entry then return end

    -- A greyed row explains itself and leaves the eye open. Closing it would hide the
    -- very message the player opened the menu to read.
    if entry.blocked then
        V.Notify(entry.blocked, 'error')
        return
    end

    -- An empty submenu is a no-op, not a close.
    if entry.opt.menu then pushMenu(entry) return end

    -- Tear the eye's focus down BEFORE running: an option that opens its own menu (a shop,
    -- an inventory) must be the one holding focus when it does.
    stopEye()
    runOption(entry.opt, entry.data)
end

-- ══════════════════════════════════════════════════════════════
-- The eye
-- ══════════════════════════════════════════════════════════════
local highlighted = nil

-- Look and attack only. Movement, sprint, jump and crouch stay live so the player can walk
-- up to what they are pointing at without closing the menu first.
local DISABLED = {
    1, 2, 3, 4,                                       -- look
    24, 25, 68, 69, 70, 91, 92, 114, 121,             -- attack / aim, on foot and in a vehicle
    140, 141, 142, 257, 263, 264,                     -- melee
    37, 12, 13, 14, 15, 16, 17,                       -- weapon wheel and scroll
    157, 158, 159, 160, 161, 162, 163, 164, 165, 166, -- weapon slots 1..0, which are our row keys
}

local function clearHighlight()
    if highlighted and DoesEntityExist(highlighted) then SetEntityDrawOutline(highlighted, false) end
    highlighted = nil
end

local function setHighlight(entity)
    if entity == highlighted then return end
    clearHighlight()
    if entity and DoesEntityExist(entity) then
        local o = Config.Outline
        SetEntityDrawOutlineColor(o.r, o.g, o.b, o.a)
        SetEntityDrawOutline(entity, true)
        highlighted = entity
    end
end

-- Idempotent teardown: an option that opens its OWN menu must keep focus, so the eye tears
-- down exactly once and never again after the option has run.
local eyeTornDown = true
stopEye = function()
    if eyeTornDown then return end
    eyeTornDown = true
    active = false
    Stack = {}
    clearHighlight()
    rayHandle, hitEntity, hitCoords = nil, nil, nil
    SetNuiFocus(false, false)
    SetNuiFocusKeepInput(false)
    exports['v-core']:MenuClosed('v-target')
    SendNUIMessage({ action = 'eyeoff' })
end

-- The eye closes on the page's Alt keyup ('closeeye'), on Escape or right-click, on a
-- selection, on the page losing focus, or on a second Alt press. It never trusts
-- RegisterKeyMapping's '-vtarget' nor an IsControlPressed poll: both are fabricated once
-- SetNuiFocus grabs the keyboard mid-hold, and the eye blinked open and shut in a loop.
local function openEye()
    if active or exports['v-core']:IsAnyMenuOpen() then return end
    if not setting('enabled', true) then return end

    active, eyeTornDown = true, false
    Stack = { { entries = {}, title = nil } }
    rayHandle, hitEntity, hitCoords = nil, nil, nil

    SetNuiFocus(true, true)
    SetNuiFocusKeepInput(true)                       -- keep walking while the menu is up
    SendNUIMessage({ action = 'eyeon', hints = {
        nav = L('tgt.hint_nav'), pick = L('tgt.hint_pick'), close = L('tgt.hint_close'),
    } })
    exports['v-core']:MenuOpened('v-target')

    CreateThread(function()
        local lastRefresh, lastKey = 0, nil
        local refreshMs = tonumber(setting('refreshMs', Config.RefreshMs)) or Config.RefreshMs

        while active do
            -- A frame error must never leave the eye frozen holding NUI focus.
            local ok, err = pcall(function()
                for _, c in ipairs(DISABLED) do DisableControlAction(0, c, true) end

                -- While a submenu is open the target is committed: re-collecting would
                -- rebuild the list under a player who has already chosen what they are
                -- acting on.
                if #Stack <= 1 then
                    local root = Stack[1]
                    local was  = hitEntity
                    stepRay()

                    local now = GetGameTimer()
                    if hitEntity ~= was or (now - lastRefresh) >= refreshMs then
                        lastRefresh = now
                        local entries, title, isSelf = collect()
                        root.entries, root.title, root.isSelf = entries, title, isSelf

                        setHighlight(#entries > 0 and hitEntity or nil)

                        -- Only message the page when the list actually changed. Rebuilding
                        -- the DOM every frame is what made the list flicker under the cursor.
                        local key = tostring(#entries) .. '|' .. tostring(title)
                        for _, e in ipairs(entries) do
                            key = key .. '|' .. tostring(e.opt.label) .. tostring(e.blocked)
                        end
                        if key ~= lastKey then
                            lastKey = key
                            SendNUIMessage(payload(root))
                        end
                    end
                end
            end)
            if not ok then
                print(('[v-target] eye frame error, eye closed: %s'):format(tostring(err)))
                break
            end
            Wait(0)
        end
        stopEye()
    end)
end

-- ══════════════════════════════════════════════════════════════
-- NUI
-- ══════════════════════════════════════════════════════════════
RegisterNUICallback('select', function(data, cb)
    local i = data and tonumber(data.index)
    if active and i then chooseRow(i) end
    cb('ok')
end)

RegisterNUICallback('back', function(_, cb)
    if active and #Stack > 1 then
        Stack[#Stack] = nil
        SendNUIMessage(payload(Stack[#Stack]))
    end
    cb('ok')
end)

RegisterNUICallback('closeeye', function(_, cb)
    -- Escape inside a submenu steps back rather than closing outright: losing the whole
    -- menu because you wanted to leave one sub-list is the classic version of this bug.
    if active and #Stack > 1 then
        Stack[#Stack] = nil
        SendNUIMessage(payload(Stack[#Stack]))
    else
        active = false
    end
    cb('ok')
end)

RegisterCommand('+vtarget', function() if active then stopEye() else openEye() end end, false)
RegisterCommand('-vtarget', function() end, false)
RegisterKeyMapping('+vtarget', 'Interaction eye (target)', 'keyboard', Config.Key or 'LMENU')

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then
        active = false; clearHighlight()
        SetNuiFocus(false, false); SetNuiFocusKeepInput(false)
        SendNUIMessage({ action = 'eyeoff' })
    end
end)

-- ══════════════════════════════════════════════════════════════
-- Debug draw
-- ══════════════════════════════════════════════════════════════
CreateThread(function()
    while true do
        local wait = 1000
        if setting('debug', Config.Debug) then
            wait = 0
            local me = GetEntityCoords(PlayerPedId())
            for _, z in pairs(Zones) do
                local c = zoneCentre(z)
                if #(me - c) < 60.0 then
                    if z.kind == 'sphere' then
                        DrawMarker(28, c.x, c.y, c.z, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
                            z.radius, z.radius, z.radius, 255, 106, 26, 45, false, false, 2, false, nil, nil, false)
                    elseif z.kind == 'poly' then
                        local n = #z.points
                        local top = z.z + (z.height or 3.0)
                        for i = 1, n do
                            local a, b = z.points[i], z.points[(i % n) + 1]
                            DrawLine(a.x, a.y, z.z, b.x, b.y, z.z, 255, 106, 26, 180)
                            DrawLine(a.x, a.y, top, b.x, b.y, top, 255, 106, 26, 180)
                            DrawLine(a.x, a.y, z.z, a.x, a.y, top, 255, 106, 26, 120)
                        end
                    else
                        DrawMarker(1, c.x, c.y, c.z - z.size.z, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
                            z.size.x * 2, z.size.y * 2, z.size.z * 2, 255, 106, 26, 45, false, false, 2, false, nil, nil, false)
                    end
                end
            end
        end
        Wait(wait)
    end
end)

-- ══════════════════════════════════════════════════════════════
-- Public API
-- ══════════════════════════════════════════════════════════════
-- Every Add* returns a handle. Keeping it lets a resource remove exactly what it added,
-- which matters because a module that restarts otherwise doubles every one of its rows.
local function addTo(group, options, owner)
    local ids = {}
    for _, o in ipairs(options or {}) do
        seq = seq + 1
        o.__id, o.__owner = seq, owner
        group[#group + 1] = o
        ids[#ids + 1] = seq
    end
    return ids
end

local function removeFrom(group, pred)
    for i = #group, 1, -1 do if pred(group[i]) then table.remove(group, i) end end
end

local GROUPS = {
    player = GlobalPlayer, ped = GlobalPed, vehicle = GlobalVehicle,
    object = GlobalObject, ['self'] = GlobalSelf,
}

exports('AddGlobalPlayer',  function(o) return addTo(GlobalPlayer,  o, GetInvokingResource()) end)
exports('AddGlobalPed',     function(o) return addTo(GlobalPed,     o, GetInvokingResource()) end)
exports('AddGlobalVehicle', function(o) return addTo(GlobalVehicle, o, GetInvokingResource()) end)
exports('AddGlobalObject',  function(o) return addTo(GlobalObject,  o, GetInvokingResource()) end)
exports('AddSelf',          function(o) return addTo(GlobalSelf,    o, GetInvokingResource()) end)

exports('AddModel', function(models, options)
    local owner = GetInvokingResource()
    if type(models) ~= 'table' then models = { models } end
    local ids = {}
    for _, m in ipairs(models) do
        local hash = (type(m) == 'string') and joaat(m) or m
        Models[hash] = Models[hash] or {}
        for _, id in ipairs(addTo(Models[hash], options, owner)) do ids[#ids + 1] = id end
    end
    return ids
end)

exports('AddEntity', function(netId, options)
    Entities[netId] = Entities[netId] or {}
    return addTo(Entities[netId], options, GetInvokingResource())
end)

exports('RemoveModel', function(model, ids)
    local hash = (type(model) == 'string') and joaat(model) or model
    if not Models[hash] then return end
    local want
    if ids then
        want = {}
        for _, id in ipairs(ids) do want[id] = true end
    end
    removeFrom(Models[hash], function(o) return (not want) or want[o.__id] end)
end)

exports('RemoveEntity', function(netId) Entities[netId] = nil end)

--- Remove by handle from any global group, or by owning resource. The second form is what
--- a module calls in onResourceStop so it leaves nothing behind.
exports('RemoveGlobal', function(group, ids)
    local g = GROUPS[group]
    if not g then return end
    local want = {}
    for _, id in ipairs(ids or {}) do want[id] = true end
    removeFrom(g, function(o) return want[o.__id] end)
end)

exports('RemoveResource', function(resource)
    for _, g in pairs(GROUPS)   do removeFrom(g, function(o) return o.__owner == resource end) end
    for _, g in pairs(Models)   do removeFrom(g, function(o) return o.__owner == resource end) end
    for _, g in pairs(Entities) do removeFrom(g, function(o) return o.__owner == resource end) end
    for name, z in pairs(Zones) do if z.owner == resource then Zones[name] = nil end end
end)

-- ── Zones ──────────────────────────────────────────────────────
exports('AddBoxZone', function(name, coords, size, options, opts)
    name = name or nextName()
    Zones[name] = {
        kind = 'box', coords = coords, size = size, options = options,
        heading = (opts and opts.heading) or 0.0,
        label = opts and opts.label or nil,
        owner = GetInvokingResource(),
    }
    return name
end)

exports('AddSphereZone', function(name, coords, radius, options, opts)
    name = name or nextName()
    Zones[name] = {
        kind = 'sphere', coords = coords, radius = radius, options = options,
        label = opts and opts.label or nil, owner = GetInvokingResource(),
    }
    return name
end)

--- points: a list of vectors in order around the shape. `z` is the floor and `height` how
--- far up it reaches, because a flat polygon would also catch whatever is on the roof.
exports('AddPolyZone', function(name, points, options, opts)
    name = name or nextName()
    Zones[name] = {
        kind = 'poly', points = points, options = options,
        z = (opts and opts.z) or 0.0, height = (opts and opts.height) or 3.0,
        label = opts and opts.label or nil, owner = GetInvokingResource(),
    }
    return name
end)

exports('RemoveZone',  function(name) Zones[name] = nil end)
exports('ZoneExists',  function(name) return Zones[name] ~= nil end)

-- ── State ──────────────────────────────────────────────────────
exports('IsActive',  function() return active end)
exports('Close',     function() stopEye() end)
exports('GetTarget', function() return hitEntity, hitCoords end)

--- What the eye would offer right now, without opening it. Useful to a module that wants
--- to know whether it has anything to say about what the player is looking at.
exports('PeekOptions', function()
    local entries = collect()
    local out = {}
    for i, e in ipairs(entries) do
        out[i] = { label = L(e.opt.label), icon = e.opt.icon, blocked = e.blocked }
    end
    return out
end)

-- ── Theme ──────────────────────────────────────────────────────
-- A NUI page can only be messaged by the resource that owns it, so v-ui cannot reach this
-- one directly: it publishes a version and each module forwards it into its own page.
local function pushTheme()
    if GetResourceState('v-ui') ~= 'started' then return end
    SendNUIMessage({ action = 'v-ui:theme', version = exports['v-ui']:Version() })
end

AddEventHandler('v-ui:client:themeChanged', function() pushTheme() end)
CreateThread(function() Wait(4000); pushTheme() end)
