-- v-banking | client
local Core = exports['v-core']:GetCore()
local isOpen = false

local atmHashes = {}
for _, name in ipairs(Config.AtmModels) do atmHashes[#atmHashes + 1] = GetHashKey(name) end

local function nearAtm()
    local c = GetEntityCoords(PlayerPedId())
    for _, hash in ipairs(atmHashes) do
        if GetClosestObjectOfType(c.x, c.y, c.z, Config.Distance, hash, false, false, false) ~= 0 then
            return true
        end
    end
    return false
end

local function helpText()
    BeginTextCommandDisplayHelp('STRING')
    AddTextComponentSubstringPlayerName('~INPUT_CONTEXT~ ' .. L('bank.help'))
    EndTextCommandDisplayHelp(0, false, true, -1)
end

local function openBank()
    if isOpen then return end
    Core.TriggerCallback('v-banking:getData', function(data)
        if not data then return end
        isOpen = true
        SetNuiFocus(true, true)   -- focus is per-resource: only the page owner may take it
        exports['v-core']:MenuOpened()
        SendNUIMessage({
            action  = 'open',
            data    = data,
            strings = Locales[(LocalPlayer.state and LocalPlayer.state.lang) or 'fr'] or {},
        })
    end)
end

-- Interaction loop near ATMs.
CreateThread(function()
    while true do
        local wait = 800
        if not isOpen and nearAtm() then
            wait = 0
            helpText()
            if IsControlJustReleased(0, Config.OpenControl) then openBank() end
        end
        Wait(wait)
    end
end)

RegisterNUICallback('close', function(_, cb)
    isOpen = false
    SetNuiFocus(false, false)
    exports['v-core']:MenuClosed()
    cb('ok')
end)

RegisterNUICallback('deposit', function(data, cb)
    Core.TriggerCallback('v-banking:deposit', function(res) cb(res or false) end, data.amount)
end)

RegisterNUICallback('withdraw', function(data, cb)
    Core.TriggerCallback('v-banking:withdraw', function(res) cb(res or false) end, data.amount)
end)

RegisterNUICallback('transfer', function(data, cb)
    Core.TriggerCallback('v-banking:transfer', function(res) cb(res or false) end, data)
end)

-- The card counter. Reading is free; ordering is charged and re-validated server-side.
RegisterNUICallback('card', function(_, cb)
    Core.TriggerCallback('v-banking:card', function(res) cb(res or { error = 'x' }) end)
end)

RegisterNUICallback('requestCard', function(_, cb)
    Core.TriggerCallback('v-banking:requestCard', function(res) cb(res or { error = 'x' }) end)
end)

-- Never leave a player's cursor/controls stuck if the resource is restarted mid-use.
AddEventHandler('onResourceStop', function(resName)
    if resName ~= GetCurrentResourceName() then return end
    SetNuiFocus(false, false)
    exports['v-core']:MenuClosed()
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
