-- v-target | built-in framework interactions
--
-- The catalogue that makes the eye the player's main interaction surface rather than a
-- context menu bolted onto a few props.
--
-- **Nothing here reimplements another module.** Where a module already owns an action
-- behind a keybind command, this delegates to that command; where it owns one behind a
-- server callback, this calls the callback. Both paths keep the module's own validation,
-- its own notifications and its own settings. A copy of those rules living here would
-- drift from the original the first time either side changed.
--
-- Everything is registered from ONE thread after a short wait, so a module that is
-- stopped at boot simply never has its rows offered -- the `has()` checks below are
-- evaluated per frame, not once, so starting it later brings its rows back.

local function has(res) return GetResourceState(res) == 'started' end
local function hasInv() return has('v-inventory') end

local function strings()
    return Locales[(LocalPlayer.state and LocalPlayer.state.lang) or 'fr'] or Locales.fr or {}
end
local function L(k) return strings()[k] or k end

-- A keybind-backed action. The command carries the module's own guards and messages, so
-- calling it is strictly better than repeating them.
local function cmd(name) return function() ExecuteCommand(name) end end

-- Admin panel action: the SERVER re-checks the permission on every one of these, so the
-- `permission` field below only decides whether the row is drawn.
local function adminAct(d)
    if has('v-admin') then V.Request('v-admin:action', function() end, d) end
end

-- A police callback, with the one message the officer needs when it refuses.
local function police(name, data)
    V.Request('v-police:' .. name, function(res)
        if not res or res.error then V.Notify(L('tgt.err_' .. ((res and res.error) or 'x')), 'error') end
    end, data)
end

-- Which seat a door bone belongs to. Pointing at the rear passenger door and getting the
-- driver's seat is the kind of thing that makes an interaction menu feel broken.
local SEAT_OF_BONE = {
    door_dside_f = -1, door_pside_f = 0,
    door_dside_r =  1, door_pside_r = 2,
}

CreateThread(function()
    Wait(500)
    local T = exports['v-target']

    -- ══════════════════════════════════════════════════════════
    -- Self  (the eye pointed at nothing targetable)
    -- ══════════════════════════════════════════════════════════
    T:AddSelf({
        { label = 'tgt.self_inv', icon = 'bag', priority = 10,
          canInteract = function() return hasInv() end,
          action = cmd('vinv') },

        { label = 'tgt.self_hands', icon = 'hands', priority = 15,
          action = cmd('handsup') },

        -- Vehicle controls, only while actually driving. They live behind one row because
        -- six separate rows would bury everything else the player can do.
        { label = 'tgt.self_vehicle', icon = 'wheel', priority = 20,
          canInteract = function() return has('v-vehicles') and IsPedInAnyVehicle(PlayerPedId(), false) end,
          menu = {
            { label = 'tgt.veh_engine', icon = 'engine', action = cmd('vveh_engine') },
            { label = 'tgt.veh_left',   icon = 'flag',   action = cmd('vveh_left') },
            { label = 'tgt.veh_right',  icon = 'flag',   action = cmd('vveh_right') },
            { label = 'tgt.veh_haz',    icon = 'flag',   action = cmd('vveh_haz') },
            { label = 'tgt.veh_seat',   icon = 'seat',   action = cmd('vveh_seat') },
            { label = 'tgt.veh_belt',   icon = 'shield', action = cmd('vveh_belt') },
            { label = 'tgt.veh_lock',   icon = 'lock',   action = cmd('vveh_lock') },
          } },

        -- Work. One row per module that is actually running, so an operator who stops
        -- v-bossmenu does not leave a dead entry behind.
        { label = 'tgt.self_work', icon = 'work', priority = 30,
          canInteract = function() return has('v-bossmenu') or has('v-police') end,
          menu = {
            { label = 'tgt.work_boss', icon = 'work', canInteract = function() return has('v-bossmenu') end,
              action = cmd('vboss') },
            { label = 'tgt.work_police', icon = 'shield', job = { 'police', 'sheriff' },
              canInteract = function() return has('v-police') end,
              action = cmd('vpolice') },
          } },

        { label = 'tgt.self_comms', icon = 'radio', priority = 40,
          canInteract = function() return has('v-radio') or has('v-music') end,
          menu = {
            { label = 'tgt.comms_radio', icon = 'radio', canInteract = function() return has('v-radio') end,
              action = cmd('vradio') },
            { label = 'tgt.comms_music', icon = 'music', canInteract = function() return has('v-music') end,
              action = cmd('vmusic') },
          } },

        -- Leaving a property is a self action, not a door action: inside the shell there
        -- is no door entity to point at.
        { label = 'tgt.self_leave_house', icon = 'house', priority = 5,
          canInteract = function() return has('v-housing') and exports['v-housing']:IsInside() ~= nil end,
          action = function()
            V.Request('v-housing:exit', function() end)
          end },

        { label = 'tgt.self_house_stash', icon = 'box', priority = 6,
          canInteract = function() return has('v-housing') and exports['v-housing']:IsInside() ~= nil end,
          action = function()
            V.Request('v-housing:stash', function(res)
                if not (res and res.ok) then V.Notify(L('tgt.err_denied'), 'error') end
            end)
          end },

        { label = 'tgt.self_admin', icon = 'shield', permission = 'admin', priority = 90,
          action = cmd('vadmin_panel') },
    })

    -- ══════════════════════════════════════════════════════════
    -- Vehicles  (bone aware)
    -- ══════════════════════════════════════════════════════════
    T:AddGlobalVehicle({
        -- ── Boot ──
        { label = 'tgt.trunk', icon = 'trunk', bones = { 'boot' }, distance = 4.5, priority = 10,
          canInteract = function(e, d, c, data)
              if not hasInv() then return false end
              if not data.netId then return false, 'tgt.err_notnet' end
              return true
          end,
          action = function(data) TriggerServerEvent('v-inventory:server:openStash', data.netId, 'inv.trunk', 'trunk') end },

        { label = 'tgt.boot', icon = 'trunk', bones = { 'boot' }, distance = 5.0, priority = 11,
          action = function(data)
              local v = data.entity
              if GetVehicleDoorAngleRatio(v, 5) > 0.1 then SetVehicleDoorShut(v, 5, false)
              else SetVehicleDoorOpen(v, 5, false, false) end
          end },

        -- ── Bonnet ──
        { label = 'tgt.hood', icon = 'hood', bones = { 'bonnet', 'engine' }, distance = 5.0, priority = 10,
          action = function(data)
              local v = data.entity
              if GetVehicleDoorAngleRatio(v, 4) > 0.1 then SetVehicleDoorShut(v, 4, false)
              else SetVehicleDoorOpen(v, 4, false, false) end
          end },

        { label = 'tgt.diagnose', icon = 'wrench', bones = { 'bonnet', 'engine' }, distance = 5.0, priority = 12,
          job = 'mechanic',
          canInteract = function() return has('v-mechanic') end,
          action = function(data)
              local plate = GetVehicleNumberPlateText(data.entity):gsub('%s+$', '')
              V.Request('v-mechanic:diagnose', function(res)
                  if not res or res.error then V.Notify(L('tgt.err_' .. ((res and res.error) or 'x')), 'error') end
              end, { plate = plate })
          end },

        -- ── Doors ──
        { label = 'tgt.door_one', icon = 'door', distance = 4.0, priority = 8,
          bones = { 'door_dside_f', 'door_dside_r', 'door_pside_f', 'door_pside_r' },
          action = function(data)
              local v = data.entity
              local idx = ({ door_dside_f = 0, door_pside_f = 1, door_dside_r = 2, door_pside_r = 3 })[data.bone]
              if not idx then return end
              if GetVehicleDoorAngleRatio(v, idx) > 0.1 then SetVehicleDoorShut(v, idx, false)
              else SetVehicleDoorOpen(v, idx, false, false) end
          end },

        { label = 'tgt.enter_seat', icon = 'seat', distance = 3.5, priority = 5,
          bones = { 'door_dside_f', 'door_dside_r', 'door_pside_f', 'door_pside_r' },
          canInteract = function(e)
              if IsPedInAnyVehicle(PlayerPedId(), false) then return false end
              return not (GetVehicleDoorLockStatus(e) == 2), 'tgt.err_locked'
          end,
          action = function(data)
              local seat = SEAT_OF_BONE[data.bone]
              if not seat then return end
              -- Free seat only: shoving the occupant out is a jack, and a jack is not
              -- something a menu row should do silently.
              if not IsVehicleSeatFree(data.entity, seat) then V.Notify(L('tgt.err_occupied'), 'error') return end
              TaskEnterVehicle(PlayerPedId(), data.entity, 10000, seat, 1.0, 1, 0)
          end },

        { label = 'tgt.glovebox', icon = 'box', distance = 4.0, priority = 9,
          bones = { 'door_dside_f', 'door_pside_f' },
          canInteract = function(e, d, c, data)
              if not hasInv() then return false end
              if not data.netId then return false, 'tgt.err_notnet' end
              return true
          end,
          action = function(data) TriggerServerEvent('v-inventory:server:openStash', data.netId, 'inv.glovebox', 'glovebox') end },

        -- ── Anywhere on the vehicle ──
        { label = 'tgt.lock', icon = 'lock', distance = 5.0, priority = 20,
          canInteract = function() return has('v-vehicles') end,
          action = cmd('vveh_lock') },

        { label = 'tgt.lockpick', icon = 'key', distance = 3.0, priority = 60,
          canInteract = function(e)
              if not has('v-vehicles') then return false end
              return GetVehicleDoorLockStatus(e) == 2, 'tgt.err_unlocked'
          end,
          action = cmd('vveh_pick') },

        { label = 'tgt.flip', icon = 'flip', distance = 5.0, priority = 40,
          canInteract = function(e) return math.abs(GetEntityRoll(e)) > 70.0 end,
          action = function(data) SetVehicleOnGroundProperly(data.entity) end },

        -- ── Police ──
        { label = 'tgt.impound', icon = 'shield', distance = 8.0, priority = 30,
          job = { 'police', 'sheriff' },
          canInteract = function(e, d, c, data)
              if not has('v-police') then return false end
              if not data.netId then return false, 'tgt.err_notnet' end
              return true
          end,
          action = function(data) police('impound', { netid = data.netId }) end },

        -- ── Admin ──
        { label = 'tgt.a_vehicle', icon = 'shield', permission = 'admin', distance = 8.0, priority = 95,
          menu = {
            { label = 'tgt.repair', icon = 'wrench', action = function(data)
                local v = data.entity
                SetVehicleFixed(v); SetVehicleDeformationFixed(v)
                SetVehicleEngineHealth(v, 1000.0); SetVehicleDirtLevel(v, 0.0)
            end },
            { label = 'tgt.clean', icon = 'clean', action = function(data) SetVehicleDirtLevel(data.entity, 0.0) end },
            { label = 'tgt.a_unlock', icon = 'unlock', action = function(data) SetVehicleDoorsLocked(data.entity, 1) end },
            { label = 'tgt.a_plate', icon = 'plate', action = function(data)
                local plate = GetVehicleNumberPlateText(data.entity):gsub('%s+$', '')
                V.Notify(plate ~= '' and plate or L('tgt.err_x'), 'info')
            end },
          } },
    })

    -- ══════════════════════════════════════════════════════════
    -- Players
    -- ══════════════════════════════════════════════════════════
    T:AddGlobalPlayer({
        { label = 'tgt.frisk', icon = 'search', distance = 2.5, priority = 20,
          canInteract = function(e, d, c, data) return hasInv() and data.playerServerId ~= nil end,
          action = function(data) TriggerServerEvent('v-inventory:server:searchPlayer', data.playerServerId) end },

        -- Police work, grouped. An officer standing over a suspect should not have to read
        -- past four admin rows to find the handcuffs.
        { label = 'tgt.police', icon = 'shield', distance = 3.0, priority = 10,
          job = { 'police', 'sheriff' },
          canInteract = function() return has('v-police') end,
          menu = {
            { label = 'tgt.pol_cuff',   icon = 'cuff',   action = function(d) police('cuff',   { target = d.playerServerId }) end },
            { label = 'tgt.pol_escort', icon = 'drag',   action = function(d) police('escort', { target = d.playerServerId }) end },
            { label = 'tgt.pol_search', icon = 'search', action = function(d) police('search', { target = d.playerServerId }) end },
          } },

        -- Admin moderation. The server re-checks the permission on every action, so this
        -- gate only keeps the rows out of a civilian's menu.
        { label = 'tgt.a_player', icon = 'shield', permission = 'admin', distance = 30.0, priority = 95,
          menu = {
            { label = 'tgt.a_heal',     icon = 'heal',   action = function(d) adminAct({ type = 'heal',   target = d.playerServerId }) end },
            { label = 'tgt.a_freeze',   icon = 'freeze', action = function(d) adminAct({ type = 'freeze', target = d.playerServerId, state = true }) end },
            { label = 'tgt.a_unfreeze', icon = 'freeze', action = function(d) adminAct({ type = 'freeze', target = d.playerServerId, state = false }) end },
            { label = 'tgt.a_bring',    icon = 'tp',     action = function(d) adminAct({ type = 'bring',  target = d.playerServerId }) end },
            { label = 'tgt.a_goto',     icon = 'tp',     action = function(d) adminAct({ type = 'goto',   target = d.playerServerId }) end },
            { label = 'tgt.a_spectate', icon = 'eye',    action = function(d) adminAct({ type = 'spectate', target = d.playerServerId }) end },
            { label = 'tgt.a_inv',      icon = 'box',
              canInteract = function(e, dist, c, d) return hasInv() and d.playerServerId ~= nil end,
              action = function(d) TriggerServerEvent('v-inventory:server:adminOpenInv', d.playerServerId) end },
          } },
    })

    -- ══════════════════════════════════════════════════════════
    -- Peds
    -- ══════════════════════════════════════════════════════════
    -- Deliberately thin. A ped is scenery until a module gives it a reason to exist, and
    -- inventing interactions for ambient pedestrians is how a target menu becomes noise.
    T:AddGlobalPed({
        { label = 'tgt.a_ped_del', icon = 'shield', permission = 'admin', distance = 12.0, priority = 95,
          canInteract = function(e) return not IsPedAPlayer(e) end,
          action = function(data)
              local e = data.entity
              SetEntityAsMissionEntity(e, true, true)
              DeleteEntity(e)
          end },
    })
end)

-- A module that restarts must not leave duplicate rows behind, and the eye is the one
-- registry that every module writes into.
AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then exports['v-target']:RemoveResource(res) end
end)
