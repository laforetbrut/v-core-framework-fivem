-- v-shops | client
-- Store locations are LIVE: the server pushes the admin-managed list (v-world) and
-- this file rebuilds blips, clerk peds and v-target zones on the fly. Config.Locations
-- is only the bootstrap fallback used before the first push / when v-world is absent.
local Core = exports['v-core']:GetCore()
local isOpen  = false
local spawned = {}   -- [locIndex] = ped
local blips   = {}   -- blip handles
local zones   = {}   -- v-target zone names

-- Bootstrap from the static config; replaced by the server push.
local Locations = {}
for _, l in ipairs(Config.Locations or {}) do
    Locations[#Locations + 1] = { shop = l.shop, x = l.coords.x, y = l.coords.y, z = l.coords.z,
                                  w = l.coords.w, ped = l.ped, noPed = l.noPed == true, noBlip = l.noBlip == true }
end

local function strings()
    return Locales[(LocalPlayer.state and LocalPlayer.state.lang) or 'fr'] or Locales.fr or {}
end

local function openShop(shopId)
    if isOpen then return end
    Core.TriggerCallback('v-shops:getShop', function(data)
        if not data then return end
        isOpen = true
        SetNuiFocus(true, true)   -- focus is per-resource: only the page owner may take it
        exports['v-core']:MenuOpened()
        SendNUIMessage({ action = 'open', shop = data, strings = strings() })
    end, shopId)
end

-- ── (Re)build the world presence for the current location list ─
local function clearWorld()
    for _, b in ipairs(blips) do if DoesBlipExist(b) then RemoveBlip(b) end end
    blips = {}
    for i, p in pairs(spawned) do
        if DoesEntityExist(p) then DeletePed(p) end
        spawned[i] = nil
    end
    if GetResourceState('v-target') == 'started' then
        for _, name in ipairs(zones) do pcall(function() exports['v-target']:RemoveZone(name) end) end
    end
    zones = {}
end

local TGT_LABEL = { convenience = 'tgt.shop', vending = 'tgt.vending', blackmarket = 'tgt.dealer',
                    launderer = 'tgt.launder', scrapyard = 'tgt.scrap' }
local TGT_ICON  = { vending = 'shop', blackmarket = 'cash', launderer = 'cash', scrapyard = 'cash' }

local function buildWorld()
    clearWorld()
    for _, loc in ipairs(Locations) do
        -- map blip
        if not loc.noBlip then
            local blip = AddBlipForCoord(loc.x, loc.y, loc.z)
            SetBlipSprite(blip, Config.Blip.sprite)
            SetBlipColour(blip, Config.Blip.color)
            SetBlipScale(blip, Config.Blip.scale)
            SetBlipAsShortRange(blip, true)
            BeginTextCommandSetBlipName('STRING')
            AddTextComponentSubstringPlayerName(strings()['shop.blip'] or 'Store')
            EndTextCommandSetBlipName(blip)
            blips[#blips + 1] = blip
        end
        -- v-target zone (point the eye at the counter)
        if GetResourceState('v-target') == 'started' then
            local shopId = loc.shop
            local ok, name = pcall(function()
                return exports['v-target']:AddSphereZone(nil, vector3(loc.x, loc.y, loc.z), 2.4, {
                    { label = TGT_LABEL[shopId] or 'tgt.shop', icon = TGT_ICON[shopId] or 'shop', distance = 2.6,
                      action = function() openShop(shopId) end },
                })
            end)
            if ok and name then zones[#zones + 1] = name end
        end
    end
end

-- Server pushes the authoritative (admin-managed) list.
RegisterNetEvent('v-shops:client:locations', function(list)
    if type(list) ~= 'table' then return end
    Locations = list
    buildWorld()
end)

CreateThread(function()
    Wait(1200)
    buildWorld()                                   -- render the bootstrap list immediately
    Wait(1500)
    TriggerServerEvent('v-shops:server:requestLocations')
end)

-- ── Clerk peds (streamed near the player) ──────────────────────
CreateThread(function()
    while true do
        Wait(1500)
        local coords = GetEntityCoords(PlayerPedId())
        for i, loc in ipairs(Locations) do
            if loc.noPed then goto continue end
            local d = #(coords - vector3(loc.x, loc.y, loc.z))
            if d < 45.0 and not (spawned[i] and DoesEntityExist(spawned[i])) then
                local model = GetHashKey(loc.ped or 'mp_m_shopkeep_01')
                RequestModel(model)
                local t = 0
                while not HasModelLoaded(model) and t < 50 do Wait(20); t = t + 1 end
                if HasModelLoaded(model) then
                    local ped = CreatePed(4, model, loc.x, loc.y, loc.z - 1.0, loc.w or 0.0, false, false)
                    SetEntityInvincible(ped, true)
                    FreezeEntityPosition(ped, true)
                    SetBlockingOfNonTemporaryEvents(ped, true)
                    spawned[i] = ped
                    SetModelAsNoLongerNeeded(model)
                end
            elseif d >= 60.0 and spawned[i] and DoesEntityExist(spawned[i]) then
                DeletePed(spawned[i]); spawned[i] = nil
            end
            ::continue::
        end
    end
end)

-- ── Interaction (press E) ──────────────────────────────────────
CreateThread(function()
    while true do
        local wait = 700
        if not isOpen then
            local coords = GetEntityCoords(PlayerPedId())
            for _, loc in ipairs(Locations) do
                if #(coords - vector3(loc.x, loc.y, loc.z)) < Config.Distance then
                    wait = 0
                    local helpKey = ({ vending = 'shop.vending_help', blackmarket = 'shop.dealer_help',
                                       launderer = 'shop.launder_help' })[loc.shop] or 'shop.help'
                    BeginTextCommandDisplayHelp('STRING')
                    AddTextComponentSubstringPlayerName('~INPUT_CONTEXT~ ' .. (strings()[helpKey] or 'Shop'))
                    EndTextCommandDisplayHelp(0, false, true, -1)
                    if IsControlJustReleased(0, 38) then openShop(loc.shop) end
                    break
                end
            end
        end
        Wait(wait)
    end
end)

-- ── NUI callbacks ──────────────────────────────────────────────
RegisterNUICallback('buy', function(data, cb)
    Core.TriggerCallback('v-shops:buy', function(res) cb(res or false) end, data)
end)

RegisterNUICallback('sell', function(data, cb)
    Core.TriggerCallback('v-shops:sell', function(res) cb(res or false) end, data)
end)

RegisterNUICallback('close', function(_, cb)
    isOpen = false
    SetNuiFocus(false, false)
    exports['v-core']:MenuClosed()
    cb('ok')
end)

AddEventHandler('onResourceStop', function(resName)
    if resName ~= GetCurrentResourceName() then return end
    SetNuiFocus(false, false)
    exports['v-core']:MenuClosed()
    clearWorld()
end)
