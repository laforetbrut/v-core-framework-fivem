-- v-crafting | client
local Core = exports['v-core']:GetCore()
local isOpen = false

local function strings()
    return Locales[(LocalPlayer.state and LocalPlayer.state.lang) or 'fr'] or Locales.fr or {}
end

local function openStation(stationId)
    if isOpen then return end
    Core.TriggerCallback('v-crafting:getStation', function(data)
        if not data then return end
        isOpen = true
        SetNuiFocus(true, true)   -- focus is per-resource: only the page owner may take it
        exports['v-core']:MenuOpened()
        SendNUIMessage({ action = 'open', station = data, strings = strings() })
    end, stationId)
end

-- ── Map blips (one per bench) ──────────────────────────────────
CreateThread(function()
    for _, st in pairs(Config.Stations) do
        for _, b in ipairs(st.benches) do
            local blip = AddBlipForCoord(b.x, b.y, b.z)
            SetBlipSprite(blip, st.blip.sprite)
            SetBlipColour(blip, st.blip.color)
            SetBlipScale(blip, st.blip.scale)
            SetBlipAsShortRange(blip, true)
            BeginTextCommandSetBlipName('STRING')
            AddTextComponentSubstringPlayerName(st.label)
            EndTextCommandSetBlipName(blip)
        end
    end
end)

-- ── Proximity: draw a marker + prompt, open on E ───────────────
CreateThread(function()
    local m = Config.Marker
    while true do
        local wait = 700
        if not isOpen then
            local coords = GetEntityCoords(PlayerPedId())
            local near
            for id, st in pairs(Config.Stations) do
                for _, b in ipairs(st.benches) do
                    local d = #(coords - vector3(b.x, b.y, b.z))
                    if d < 12.0 then
                        wait = 0
                        DrawMarker(m.type, b.x, b.y, b.z - 0.96, 0, 0, 0, 0, 0, 0,
                            m.size, m.size, m.size, m.r, m.g, m.b, m.a, false, false, 2, nil, nil, false)
                        if d < Config.Distance then near = id end
                    end
                end
            end
            if near then
                BeginTextCommandDisplayHelp('STRING')
                AddTextComponentSubstringPlayerName('~INPUT_CONTEXT~ ' .. (strings()['craft.help'] or 'Craft'))
                EndTextCommandDisplayHelp(0, false, true, -1)
                if IsControlJustReleased(0, 38) then openStation(near) end
            end
        end
        Wait(wait)
    end
end)

-- ── NUI callbacks ──────────────────────────────────────────────
RegisterNUICallback('craft', function(data, cb)
    Core.TriggerCallback('v-crafting:craft', function(res) cb(res or false) end, data)
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
end)
