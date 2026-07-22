-- v-drugs | client
-- Renders the plants, offers the interactions, and sells to a ped you are looking at.
-- Every decision (yield, price, demand, heat, whether you were seen) is the server's.

local Plants = {}
local objects = {}       -- [plantId] = entity
local placing = nil      -- substance key while placing a plant

local function strings()
    return Locales[(LocalPlayer.state and LocalPlayer.state.lang) or 'fr'] or Locales.fr or {}
end
local function L(k) return strings()[k] or k end

-- ── Plant props ────────────────────────────────────────────────
local function clearObjects()
    for id, ent in pairs(objects) do
        if DoesEntityExist(ent) then DeleteEntity(ent) end
        objects[id] = nil
    end
end

--- Props are local and non-networked: a plant is server state, and spawning it as a
--- networked entity would let any client delete somebody else's crop.
local function syncObjects()
    local me = GetEntityCoords(PlayerPedId())
    for id, r in pairs(Plants) do
        local pos = vector3(r.x + 0.0, r.y + 0.0, r.z + 0.0)
        local near = #(me - pos) < 120.0
        if near and not objects[id] then
            local model = joaat(Config.Plant.prop)
            RequestModel(model)
            local t = 0
            while not HasModelLoaded(model) and t < 60 do Wait(10); t = t + 1 end
            if HasModelLoaded(model) then
                local ent = CreateObject(model, pos.x, pos.y, pos.z, false, false, false)
                PlaceObjectOnGroundProperly(ent)
                FreezeEntityPosition(ent, true)
                SetEntityAsMissionEntity(ent, true, true)
                objects[id] = ent
            end
        elseif not near and objects[id] then
            if DoesEntityExist(objects[id]) then DeleteEntity(objects[id]) end
            objects[id] = nil
        end
    end
    for id, ent in pairs(objects) do
        if not Plants[id] then
            if DoesEntityExist(ent) then DeleteEntity(ent) end
            objects[id] = nil
        end
    end
end

RegisterNetEvent('v-drugs:client:plants', function(list)
    Plants = list or {}
    syncObjects()
end)

V.Ready(function()
    Wait(1800)
    TriggerServerEvent('v-drugs:server:request')
end)

CreateThread(function()
    while true do
        Wait(4000)
        syncObjects()
    end
end)

-- ── Planting ───────────────────────────────────────────────────
RegisterNetEvent('v-drugs:client:startPlant', function(key)
    if placing then return end
    placing = key
    V.Notify(L('drug.place_hint'), 'info')
end)

-- Only ticks while actually placing, so the prompt costs nothing the rest of the time.
CreateThread(function()
    while true do
        if placing then
            BeginTextCommandDisplayHelp('STRING')
            AddTextComponentSubstringPlayerName('~INPUT_CONTEXT~ ' .. L('drug.place') ..
                '   ~INPUT_FRONTEND_CANCEL~ ' .. L('drug.cancel'))
            EndTextCommandDisplayHelp(0, false, true, -1)

            if IsControlJustReleased(0, 38) then          -- E
                local key = placing
                placing = nil
                V.Request('v-drugs:plant', function(res)
                    if res and res.ok then V.Notify(L('drug.planted'), 'success')
                    else V.Notify(L('drug.err_' .. ((res and res.error) or 'x')), 'error') end
                end, { drug = key })
            elseif IsControlJustReleased(0, 202) then     -- Backspace / cancel
                placing = nil
                V.Notify(L('drug.cancelled'), 'info')
            end
            Wait(0)
        else
            Wait(500)
        end
    end
end)

-- ── Plant interaction ──────────────────────────────────────────
CreateThread(function()
    while true do
        local wait = 800
        if next(Plants) then
            local me = GetEntityCoords(PlayerPedId())
            for id, r in pairs(Plants) do
                local pos = vector3(r.x + 0.0, r.y + 0.0, r.z + 0.0)
                local dist = #(me - pos)
                if dist < 3.0 then
                    wait = 0
                    -- The label says what the plant needs, so a grower can read a field at
                    -- a glance instead of interacting with each one.
                    -- Ripeness comes from the server: grow time lives on the substance
                    -- row, which the client never sees.
                    local pct = math.floor(tonumber(r.pct) or 0)
                    local ripe = pct >= 100
                    BeginTextCommandDisplayHelp('STRING')
                    AddTextComponentSubstringPlayerName(
                        ('%s %d%%   ~INPUT_CONTEXT~ %s   ~INPUT_DETONATE~ %s'):format(
                            L('drug.plant'), pct,
                            ripe and L('drug.harvest') or L('drug.unripe'),
                            L('drug.water')))
                    EndTextCommandDisplayHelp(0, false, true, -1)

                    if IsControlJustReleased(0, 38) then          -- E
                        V.Request('v-drugs:harvest', function(res)
                            if res and res.ok then
                                V.Notify((L(res.theft and 'drug.stole' or 'drug.harvested')):format(res.amount), 'success')
                            else
                                V.Notify(L('drug.err_' .. ((res and res.error) or 'x')), 'error')
                            end
                        end, { id = id })
                    elseif IsControlJustReleased(0, 47) then      -- G
                        V.Request('v-drugs:water', function(res)
                            if res and res.ok then V.Notify(L('drug.watered'), 'success')
                            else V.Notify(L('drug.err_' .. ((res and res.error) or 'x')), 'error') end
                        end, { id = id })
                    end
                    break
                end
            end
        end
        Wait(wait)
    end
end)

-- ── Street dealing ─────────────────────────────────────────────
-- Offering is an interaction with a ped you are next to, not a menu: the point of street
-- dealing is standing somewhere you should not be.
-- FiveM has no ped enumerator built in; this is the standard pool walk.
function EnumeratePeds()
    return coroutine.wrap(function()
        local handle, ped = FindFirstPed()
        local ok = true
        repeat
            coroutine.yield(ped)
            ok, ped = FindNextPed(handle)
        until not ok
        EndFindPed(handle)
    end)
end

local function nearestPed()
    local me = PlayerPedId()
    local coords = GetEntityCoords(me)
    local best, bestD = nil, Config.Street.radius
    for ped in EnumeratePeds() do
        if ped ~= me and not IsPedAPlayer(ped) and not IsPedDeadOrDying(ped, true) then
            local d = #(coords - GetEntityCoords(ped))
            if d < bestD then best, bestD = ped, d end
        end
    end
    return best
end

exports('OfferTo', function(item)
    local ped = nearestPed()
    if not ped then V.Notify(L('drug.err_noped'), 'error') return end
    TaskTurnPedToFaceEntity(PlayerPedId(), ped, 1500)
    V.Request('v-drugs:sell', function(res)
        if res and res.ok then
            V.Notify((L(res.dirty and 'drug.sold_dirty' or 'drug.sold')):format(res.price), 'success')
            if res.seen then V.Notify(L('drug.seen'), 'warning') end
        else
            V.Notify(L('drug.err_' .. ((res and res.error) or 'x')), 'error')
        end
    end, { item = item })
end)

-- Using a sellable drug offers it to whoever is standing next to you.
RegisterNetEvent('v-drugs:client:offer', function(item)
    exports['v-drugs']:OfferTo(item)
end)

-- A bust puts a temporary blip on the police map, and only theirs.
RegisterNetEvent('v-drugs:client:bustAlert', function(coords, radius)
    local b = AddBlipForRadius(coords.x + 0.0, coords.y + 0.0, coords.z + 0.0, radius + 0.0)
    SetBlipColour(b, 1); SetBlipAlpha(b, 120)
    local i = AddBlipForCoord(coords.x + 0.0, coords.y + 0.0, coords.z + 0.0)
    SetBlipSprite(i, 51); SetBlipColour(i, 1); SetBlipScale(i, 0.9)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(L('drug.alert'))
    EndTextCommandSetBlipName(i)
    V.Notify(L('drug.alert'), 'warning')
    SetTimeout(90000, function()
        if DoesBlipExist(b) then RemoveBlip(b) end
        if DoesBlipExist(i) then RemoveBlip(i) end
    end)
end)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then clearObjects() end
end)
