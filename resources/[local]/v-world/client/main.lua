-- v-world | client
-- Renders the admin-managed map blips and rebuilds them live whenever an admin
-- edits them (no reconnect / restart needed).
local handles = {}

local function clearBlips()
    for _, b in ipairs(handles) do
        if DoesBlipExist(b) then RemoveBlip(b) end
    end
    handles = {}
end

local function render(list)
    clearBlips()
    for _, r in ipairs(list or {}) do
        if r.enabled == 1 or r.enabled == true then
            local b = AddBlipForCoord(r.x + 0.0, r.y + 0.0, r.z + 0.0)
            SetBlipSprite(b, math.floor(tonumber(r.sprite) or 1))
            SetBlipColour(b, math.floor(tonumber(r.color) or 0))
            SetBlipScale(b, (tonumber(r.scale) or 0.8) + 0.0)
            SetBlipAsShortRange(b, r.shortrange == 1 or r.shortrange == true)
            BeginTextCommandSetBlipName('STRING')
            AddTextComponentSubstringPlayerName(tostring(r.label or 'Blip'))
            EndTextCommandSetBlipName(b)
            handles[#handles + 1] = b
        end
    end
end

RegisterNetEvent('v-world:client:blips', function(list) render(list) end)

-- Ask for the current set once we're in the world.
CreateThread(function()
    Wait(2500)
    TriggerServerEvent('v-world:server:request')
end)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then clearBlips() end
end)
