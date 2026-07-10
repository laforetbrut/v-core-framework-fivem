-- v-inventory | client
local Core = exports['v-core']:GetCore()
local isOpen = false
local Drops = {}   -- id -> vector3

local function strings()
    return Locales[(LocalPlayer.state and LocalPlayer.state.lang) or 'fr'] or Locales.fr or {}
end

local function openInventory()
    if isOpen then return end
    Core.TriggerCallback('v-inventory:getState', function(state)
        if not state then return end
        isOpen = true
        exports['v-core']:OpenMenu()
        SendNUIMessage({ action = 'open', state = state, strings = strings() })
    end)
end

local function closestPlayer(maxDist)
    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    local best, bestDist = nil, maxDist
    for _, pid in ipairs(GetActivePlayers()) do
        if pid ~= PlayerId() then
            local tped = GetPlayerPed(pid)
            local d = #(coords - GetEntityCoords(tped))
            if d < bestDist then best, bestDist = pid, d end
        end
    end
    return best and GetPlayerServerId(best) or nil
end

-- ── Keybind (TAB by default; rebindable in GTA key settings) ───
RegisterCommand('vinv', function() openInventory() end, false)
RegisterKeyMapping('vinv', 'Open inventory', 'keyboard', 'TAB')

-- ── NUI callbacks ──────────────────────────────────────────────
RegisterNUICallback('close', function(_, cb)
    isOpen = false
    exports['v-core']:CloseMenu()
    TriggerServerEvent('v-inventory:server:closeStash')
    cb('ok')
end)

RegisterNUICallback('move', function(data, cb)
    Core.TriggerCallback('v-inventory:move', function(state) cb(state or false) end, data)
end)

RegisterNUICallback('use', function(data, cb)
    Core.TriggerCallback('v-inventory:use', function(state) cb(state or false) end, data.slot)
end)

RegisterNUICallback('rename', function(data, cb)
    Core.TriggerCallback('v-inventory:rename', function(state) cb(state or false) end, data)
end)

RegisterNUICallback('unequipCloth', function(data, cb)
    Core.TriggerCallback('v-inventory:unequipCloth', function(state) cb(state or false) end, data.cat)
end)

RegisterNUICallback('drop', function(data, cb)
    local c = GetEntityCoords(PlayerPedId())
    data.coords = { x = c.x, y = c.y, z = c.z - 0.9 }
    Core.TriggerCallback('v-inventory:drop', function(state) cb(state or false) end, data)
end)

RegisterNUICallback('give', function(data, cb)
    local target = closestPlayer(Config.GiveDistance)
    if not target then Core.Notify(strings()['inv.no_target'], 'error'); cb(false); return end
    data.target = target
    Core.TriggerCallback('v-inventory:give', function(state) cb(state or false) end, data)
end)

-- ── Live cash mirror (banking/shops changed cash while inventory open) ──
RegisterNetEvent('v-inventory:client:cash', function(cash)
    if isOpen then SendNUIMessage({ action = 'cash', cash = cash }) end
end)

-- ── Heal from a medical item use (server-driven) ───────────────
RegisterNetEvent('v-inventory:client:heal', function(amount)
    local ped = PlayerPedId()
    local hp = GetEntityHealth(ped)
    SetEntityHealth(ped, math.min(GetEntityMaxHealth(ped), hp + math.floor((amount or 25) * 2)))
    ClearPedBloodDamage(ped)
end)

-- ── Hotbar quick-use (1..5) — uses player slots 1-5 when inventory is closed ──
for i = 1, 5 do
    RegisterCommand('vhotbar' .. i, function()
        if isOpen then return end
        Core.TriggerCallback('v-inventory:use', function() end, i)
    end, false)
    RegisterKeyMapping('vhotbar' .. i, 'Use item slot ' .. i, 'keyboard', tostring(i))
end

-- ── Secondary container opened by the server ───────────────────
RegisterNetEvent('v-inventory:client:openSecondary', function()
    openInventory()
end)

-- ── Vehicle trunk (E at the rear of a car) ─────────────────────
CreateThread(function()
    while true do
        local wait = 700
        local ped = PlayerPedId()
        if not isOpen and not IsPedInAnyVehicle(ped, false) then
            local coords = GetEntityCoords(ped)
            local veh = GetClosestVehicle(coords.x, coords.y, coords.z, 3.5, 0, 71)
            if veh ~= 0 and DoesEntityExist(veh) then
                local minDim = GetModelDimensions(GetEntityModel(veh))
                local rear = GetOffsetFromEntityInWorldCoords(veh, 0.0, (minDim.y or -2.3) + 0.15, 0.0)
                if #(coords - rear) < 1.5 then
                    wait = 0
                    BeginTextCommandDisplayHelp('STRING')
                    AddTextComponentSubstringPlayerName('~INPUT_CONTEXT~ ' .. (strings()['inv.help_trunk'] or 'Open trunk'))
                    EndTextCommandDisplayHelp(0, false, true, -1)
                    if IsControlJustReleased(0, 38) then
                        local plate = (GetVehicleNumberPlateText(veh) or ''):gsub('%s+', '')
                        TriggerServerEvent('v-inventory:server:openStash', 'trunk:' .. plate, 'inv.trunk', 'trunk')
                    end
                end
            end
        end
        Wait(wait)
    end
end)

-- ── Ground drops (markers + E to open the nearest) ─────────────
RegisterNetEvent('v-inventory:client:createDrop', function(id, coords)
    Drops[id] = vector3(coords.x + 0.0, coords.y + 0.0, coords.z + 0.0)
end)

CreateThread(function()
    while true do
        local wait = 800
        if not isOpen and next(Drops) then
            local coords = GetEntityCoords(PlayerPedId())
            local nearest, nd = nil, 1.6
            for id, dc in pairs(Drops) do
                local d = #(coords - dc)
                if d < 12.0 then
                    DrawMarker(2, dc.x, dc.y, dc.z + 0.2, 0, 0, 0, 0, 180.0, 0, 0.22, 0.22, 0.18, 255, 106, 26, 160, false, false, 2, nil, nil, false)
                    wait = 0
                    if d < nd then nearest, nd = id, d end
                end
            end
            if nearest then
                BeginTextCommandDisplayHelp('STRING')
                AddTextComponentSubstringPlayerName('~INPUT_CONTEXT~ ' .. (strings()['inv.ground'] or 'Ground'))
                EndTextCommandDisplayHelp(0, false, true, -1)
                if IsControlJustReleased(0, 38) then
                    TriggerServerEvent('v-inventory:server:openStash', nearest, 'inv.ground', 'drop')
                end
            end
        end
        Wait(wait)
    end
end)

AddEventHandler('onResourceStop', function(resName)
    if resName ~= GetCurrentResourceName() then return end
    exports['v-core']:CloseMenu()
end)
