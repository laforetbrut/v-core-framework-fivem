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
        exports['v-core']:OpenMenu()
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
    exports['v-core']:CloseMenu()
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

-- Never leave a player's cursor/controls stuck if the resource is restarted mid-use.
AddEventHandler('onResourceStop', function(resName)
    if resName ~= GetCurrentResourceName() then return end
    exports['v-core']:CloseMenu()
end)
