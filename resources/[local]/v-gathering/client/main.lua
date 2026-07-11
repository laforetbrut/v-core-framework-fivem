-- v-gathering | client
local Core = exports['v-core']:GetCore()
local busy = false

local function strings()
    return Locales[(LocalPlayer.state and LocalPlayer.state.lang) or 'fr'] or Locales.fr or {}
end
local function pretty(name) return (name:gsub('_', ' ')) end

-- ── Blips (one per node) ───────────────────────────────────────
CreateThread(function()
    for _, node in ipairs(Config.Nodes) do
        local res = Config.Resources[node.type]
        if res and res.blip then   -- illegal nodes (blip=false) stay off the map
            local blip = AddBlipForCoord(node.coords.x, node.coords.y, node.coords.z)
            SetBlipSprite(blip, res.blip.sprite)
            SetBlipColour(blip, res.blip.color)
            SetBlipScale(blip, res.blip.scale)
            SetBlipAsShortRange(blip, true)
            BeginTextCommandSetBlipName('STRING')
            AddTextComponentSubstringPlayerName(res.label)
            EndTextCommandSetBlipName(blip)
        end
    end
end)

-- Play the harvest scenario for `time` ms; abort if the player walks off the node.
local function harvest(node, res, idx)
    if busy then return end
    busy = true
    local ped = PlayerPedId()
    TaskStartScenarioInPlace(ped, res.scenario, 0, true)

    local started, done, canceled = GetGameTimer(), false, false
    while not done do
        Wait(0)
        if GetGameTimer() - started >= (res.time or 4000) then done = true break end
        if #(GetEntityCoords(ped) - node.coords) > (Config.Distance + 0.8) or IsPedRagdoll(ped) or IsEntityDead(ped) then
            canceled = true; done = true
        end
        -- draw a lightweight prompt so the player knows to hold still
        BeginTextCommandDisplayHelp('STRING')
        AddTextComponentSubstringPlayerName(strings()['gather.working'] or 'Harvesting…')
        EndTextCommandDisplayHelp(0, false, true, -1)
    end

    ClearPedTasks(ped)
    if canceled then busy = false; Core.Notify(strings()['gather.canceled'] or 'Cancelled.', 'error'); return end

    Core.TriggerCallback('v-gathering:harvest', function(res2)
        busy = false
        if not res2 or not res2.ok then
            if res2 and res2.error == 'space' then return end   -- server already notified
            return
        end
        local msg = ('+%d %s'):format(res2.amount, pretty(res2.item))
        if res2.bonus then msg = msg .. (' (+1 ' .. pretty(res2.bonus) .. ')') end
        Core.Notify(msg, 'success')
    end, { idx = idx, type = node.type })
end

-- ── Proximity: marker + prompt, harvest on E ───────────────────
CreateThread(function()
    local m = Config.Marker
    while true do
        local wait = 700
        if not busy then
            local coords = GetEntityCoords(PlayerPedId())
            local near
            for idx, node in ipairs(Config.Nodes) do
                local d = #(coords - node.coords)
                if d < 14.0 then
                    wait = 0
                    DrawMarker(m.type, node.coords.x, node.coords.y, node.coords.z - 0.95, 0, 0, 0, 0, 0, 0,
                        m.size, m.size, m.size, m.r, m.g, m.b, m.a, false, false, 2, nil, nil, false)
                    if d < Config.Distance then near = idx end
                end
            end
            if near then
                local node = Config.Nodes[near]
                local res = Config.Resources[node.type]
                BeginTextCommandDisplayHelp('STRING')
                AddTextComponentSubstringPlayerName('~INPUT_CONTEXT~ ' .. (res.label or 'Harvest'))
                EndTextCommandDisplayHelp(0, false, true, -1)
                if IsControlJustReleased(0, 38) then harvest(node, res, near) end
            end
        end
        Wait(wait)
    end
end)
