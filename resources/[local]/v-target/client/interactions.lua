-- v-target | built-in framework interactions
-- The eye is the universal interaction surface. Everything here is permission/job aware
-- and delegates the real action (and its server-side validation) to the owning module.
local Core = exports['v-core']:GetCore()
local function hasInv() return GetResourceState('v-inventory') == 'started' end
local function hasAdmin() return GetResourceState('v-admin') == 'started' end

-- Trigger an admin-panel action (the server re-checks the admin permission).
local function adminAct(d) if hasAdmin() then Core.TriggerCallback('v-admin:action', function() end, d) end end

CreateThread(function()
    Wait(500)

    -- ── Vehicles ──────────────────────────────────────────────
    exports['v-target']:AddGlobalVehicle({
        -- Storage
        { label = 'tgt.trunk', icon = 'trunk', distance = 4.5,
          canInteract = function(e, d, c, data) return hasInv() and data.netId ~= nil end,
          action = function(data) TriggerServerEvent('v-inventory:server:openStash', data.netId, 'inv.trunk', 'trunk') end },
        { label = 'tgt.glovebox', icon = 'box', distance = 4.0,
          canInteract = function(e, d, c, data) return hasInv() and data.netId ~= nil end,
          action = function(data) TriggerServerEvent('v-inventory:server:openStash', data.netId, 'inv.glovebox', 'glovebox') end },
        -- Physical controls
        { label = 'tgt.doors', icon = 'door', distance = 5.0, action = function(data)
            local v = data.entity; local anyOpen = false
            for _, d in ipairs({ 0, 1, 2, 3 }) do if GetVehicleDoorAngleRatio(v, d) > 0.1 then anyOpen = true break end end
            for _, d in ipairs({ 0, 1, 2, 3 }) do
                if anyOpen then SetVehicleDoorShut(v, d, false) else SetVehicleDoorOpen(v, d, false, false) end
            end
        end },
        { label = 'tgt.hood', icon = 'hood', distance = 5.0, action = function(data)
            local v = data.entity
            if GetVehicleDoorAngleRatio(v, 4) > 0.1 then SetVehicleDoorShut(v, 4, false) else SetVehicleDoorOpen(v, 4, false, false) end
        end },
        { label = 'tgt.boot', icon = 'trunk', distance = 5.0, action = function(data)
            local v = data.entity
            if GetVehicleDoorAngleRatio(v, 5) > 0.1 then SetVehicleDoorShut(v, 5, false) else SetVehicleDoorOpen(v, 5, false, false) end
        end },
        { label = 'tgt.engine', icon = 'engine', distance = 5.0, action = function(data)
            local v = data.entity; SetVehicleEngineOn(v, not GetIsVehicleEngineRunning(v), false, true)
        end },
        { label = 'tgt.lock', icon = 'lock', distance = 5.0, action = function(data)
            local v = data.entity
            local locked = GetVehicleDoorLockStatus(v) == 2
            SetVehicleDoorsLocked(v, locked and 1 or 2)
            Core.Notify((locked and 'Unlocked' or 'Locked'), 'info')
        end },
        { label = 'tgt.flip', icon = 'flip', distance = 5.0,
          canInteract = function(e) return math.abs(GetEntityRoll(e)) > 70.0 end,
          action = function(data) SetVehicleOnGroundProperly(data.entity) end },
        -- Admin-only vehicle moderation
        { label = 'tgt.repair', icon = 'wrench', distance = 6.0, permission = 'admin', action = function(data)
            local v = data.entity
            SetVehicleFixed(v); SetVehicleDeformationFixed(v); SetVehicleEngineHealth(v, 1000.0); SetVehicleDirtLevel(v, 0.0)
        end },
        { label = 'tgt.clean', icon = 'clean', distance = 6.0, permission = 'admin',
          action = function(data) SetVehicleDirtLevel(data.entity, 0.0) end },
    })

    -- ── Players ───────────────────────────────────────────────
    exports['v-target']:AddGlobalPlayer({
        { label = 'tgt.frisk', icon = 'search', distance = 2.5,
          canInteract = function(e, d, c, data) return hasInv() and data.playerServerId ~= nil end,
          action = function(data) TriggerServerEvent('v-inventory:server:searchPlayer', data.playerServerId) end },
        { label = 'tgt.police_search', icon = 'shield', distance = 2.5, job = 'police',
          canInteract = function(e, d, c, data) return hasInv() and data.playerServerId ~= nil end,
          action = function(data) TriggerServerEvent('v-inventory:server:searchPlayer', data.playerServerId) end },
        -- Admin moderation (server re-checks the permission on every action)
        { label = 'tgt.a_heal', icon = 'heal', permission = 'admin', distance = 8.0,
          action = function(data) adminAct({ type = 'heal', target = data.playerServerId }) end },
        { label = 'tgt.a_freeze', icon = 'freeze', permission = 'admin', distance = 8.0,
          action = function(data) adminAct({ type = 'freeze', target = data.playerServerId, state = true }) end },
        { label = 'tgt.a_unfreeze', icon = 'freeze', permission = 'admin', distance = 8.0,
          action = function(data) adminAct({ type = 'freeze', target = data.playerServerId, state = false }) end },
        { label = 'tgt.a_bring', icon = 'tp', permission = 'admin', distance = 30.0,
          action = function(data) adminAct({ type = 'bring', target = data.playerServerId }) end },
        { label = 'tgt.a_goto', icon = 'tp', permission = 'admin', distance = 30.0,
          action = function(data) adminAct({ type = 'goto', target = data.playerServerId }) end },
        { label = 'tgt.a_spectate', icon = 'eye', permission = 'admin', distance = 30.0,
          action = function(data) adminAct({ type = 'spectate', target = data.playerServerId }) end },
        { label = 'tgt.a_inv', icon = 'box', permission = 'admin', distance = 8.0,
          canInteract = function(e, d, c, data) return hasInv() and data.playerServerId ~= nil end,
          action = function(data) TriggerServerEvent('v-inventory:server:adminOpenInv', data.playerServerId) end },
    })
end)
