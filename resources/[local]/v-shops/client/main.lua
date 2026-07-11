-- v-shops | client
local Core = exports['v-core']:GetCore()
local isOpen  = false
local spawned = {}

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

-- ── Blips ──────────────────────────────────────────────────────
CreateThread(function()
    for _, loc in ipairs(Config.Locations) do
        if loc.noBlip then goto continue end
        local blip = AddBlipForCoord(loc.coords.x, loc.coords.y, loc.coords.z)
        SetBlipSprite(blip, Config.Blip.sprite)
        SetBlipColour(blip, Config.Blip.color)
        SetBlipScale(blip, Config.Blip.scale)
        SetBlipAsShortRange(blip, true)
        BeginTextCommandSetBlipName('STRING')
        AddTextComponentSubstringPlayerName(strings()['shop.blip'] or 'Store')
        EndTextCommandSetBlipName(blip)
        ::continue::
    end
end)

-- ── Clerk peds (streamed near the player) ──────────────────────
CreateThread(function()
    while true do
        Wait(1500)
        local coords = GetEntityCoords(PlayerPedId())
        for i, loc in ipairs(Config.Locations) do
            if loc.noPed then goto continue end
            local pos = vector3(loc.coords.x, loc.coords.y, loc.coords.z)
            local d = #(coords - pos)
            if d < 45.0 and not (spawned[i] and DoesEntityExist(spawned[i])) then
                local model = GetHashKey(loc.ped or 'mp_m_shopkeep_01')
                RequestModel(model)
                local t = 0
                while not HasModelLoaded(model) and t < 50 do Wait(20); t = t + 1 end
                local ped = CreatePed(4, model, loc.coords.x, loc.coords.y, loc.coords.z - 1.0, loc.coords.w, false, false)
                SetEntityInvincible(ped, true)
                FreezeEntityPosition(ped, true)
                SetBlockingOfNonTemporaryEvents(ped, true)
                spawned[i] = ped
                SetModelAsNoLongerNeeded(model)
            elseif d >= 60.0 and spawned[i] and DoesEntityExist(spawned[i]) then
                DeletePed(spawned[i]); spawned[i] = nil
            end
            ::continue::
        end
    end
end)

-- ── Interaction ────────────────────────────────────────────────
CreateThread(function()
    while true do
        local wait = 700
        if not isOpen then
            local coords = GetEntityCoords(PlayerPedId())
            for _, loc in ipairs(Config.Locations) do
                if #(coords - vector3(loc.coords.x, loc.coords.y, loc.coords.z)) < Config.Distance then
                    wait = 0
                    local helpKey = (loc.shop == 'vending') and 'shop.vending_help' or 'shop.help'
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
    for _, p in pairs(spawned) do if DoesEntityExist(p) then DeletePed(p) end end
end)
