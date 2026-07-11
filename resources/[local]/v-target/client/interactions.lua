-- v-target | built-in framework interactions
-- Registers the core interactions so the eye is the universal interaction surface.
-- Everything here is permission/job aware and delegates the real action (and its
-- server-side validation) to the owning module.
local function hasInv() return GetResourceState('v-inventory') == 'started' end

CreateThread(function()
    Wait(500)   -- let the exports settle

    -- ── Vehicles ──────────────────────────────────────────────
    exports['v-target']:AddGlobalVehicle({
        {
            label = 'tgt.trunk', icon = 'trunk', distance = 4.0,
            canInteract = function(entity, dist, coords, data) return hasInv() and data.netId ~= nil end,
            action = function(data) TriggerServerEvent('v-inventory:server:openStash', data.netId, 'inv.trunk', 'trunk') end,
        },
        {
            label = 'tgt.glovebox', icon = 'box', distance = 4.0,
            canInteract = function(entity, dist, coords, data) return hasInv() and data.netId ~= nil end,
            action = function(data) TriggerServerEvent('v-inventory:server:openStash', data.netId, 'inv.glovebox', 'glovebox') end,
        },
        {
            -- Permission-gated example: only admins see "Repair vehicle".
            label = 'tgt.repair', icon = 'wrench', distance = 5.0, permission = 'admin',
            action = function(data)
                if data.entity and data.entity ~= 0 then
                    SetVehicleFixed(data.entity); SetVehicleDeformationFixed(data.entity)
                    SetVehicleEngineHealth(data.entity, 1000.0); SetVehicleDirtLevel(data.entity, 0.0)
                end
            end,
        },
    })

    -- ── Players ───────────────────────────────────────────────
    exports['v-target']:AddGlobalPlayer({
        {
            -- Anyone can attempt a frisk; the server enforces hands-up / downed.
            label = 'tgt.frisk', icon = 'search', distance = 2.5,
            canInteract = function(entity, dist, coords, data) return hasInv() and data.playerServerId ~= nil end,
            action = function(data) TriggerServerEvent('v-inventory:server:searchPlayer', data.playerServerId) end,
        },
        {
            -- Job-gated example: only on-duty police see "Search suspect".
            label = 'tgt.police_search', icon = 'shield', distance = 2.5, job = 'police',
            canInteract = function(entity, dist, coords, data) return hasInv() and data.playerServerId ~= nil end,
            action = function(data) TriggerServerEvent('v-inventory:server:searchPlayer', data.playerServerId) end,
        },
    })
end)
