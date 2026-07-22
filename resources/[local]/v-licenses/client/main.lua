-- v-licenses | client
-- The module has no NUI of its own: the wallet is shown by the city hall, and issuing
-- happens through the target eye. This file only keeps the type list for other UIs and
-- renders the driving-school point.
local Core = exports['v-core']:GetCore()

local Types = Config.Types
local schoolBlip = nil

local function strings()
    return Locales[(LocalPlayer.state and LocalPlayer.state.lang) or 'fr'] or Locales.fr or {}
end
local function L(k) return strings()[k] or k end

RegisterNetEvent('v-licenses:client:types', function(list)
    if type(list) ~= 'table' or #list == 0 then return end
    Types = list
end)

exports('GetTypes', function() return Types end)

CreateThread(function()
    Wait(3000)
    TriggerServerEvent('v-licenses:server:request')

    local s = Config.School
    if s then
        schoolBlip = AddBlipForCoord(s.x + 0.0, s.y + 0.0, s.z + 0.0)
        SetBlipSprite(schoolBlip, s.blip.sprite); SetBlipColour(schoolBlip, s.blip.color)
        SetBlipScale(schoolBlip, s.blip.scale); SetBlipAsShortRange(schoolBlip, true)
        BeginTextCommandSetBlipName('STRING')
        AddTextComponentSubstringPlayerName(L('lic.school'))
        EndTextCommandSetBlipName(schoolBlip)
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() and schoolBlip and DoesBlipExist(schoolBlip) then
        RemoveBlip(schoolBlip)
    end
end)
