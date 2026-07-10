-- v-appearance | barber / surgeon / tattooist stations (peds, blips, E to open)
local spawned = {}   -- "mode:index" -> ped

local function strings()
    return Locales[(LocalPlayer.state and LocalPlayer.state.lang) or 'fr'] or Locales.fr or {}
end

-- Flatten the configured stations into a single point list.
local points = {}
for mode, cfg in pairs(Config.Stations) do
    for i, coords in ipairs(cfg.locations) do
        points[#points + 1] = { mode = mode, i = i, coords = coords, ped = cfg.ped, blip = cfg.blipSprite, i18n = cfg.i18n }
    end
end

-- Blips
CreateThread(function()
    for _, p in ipairs(points) do
        local blip = AddBlipForCoord(p.coords.x, p.coords.y, p.coords.z)
        SetBlipSprite(blip, p.blip or 71)
        SetBlipColour(blip, 0)
        SetBlipScale(blip, 0.7)
        SetBlipAsShortRange(blip, true)
        BeginTextCommandSetBlipName('STRING')
        AddTextComponentSubstringPlayerName(strings()[p.i18n] or 'Appearance')
        EndTextCommandSetBlipName(blip)
    end
end)

-- Stream station peds near the player
CreateThread(function()
    while true do
        Wait(1500)
        local coords = GetEntityCoords(PlayerPedId())
        for idx, p in ipairs(points) do
            local key = p.mode .. ':' .. p.i
            local d = #(coords - vector3(p.coords.x, p.coords.y, p.coords.z))
            if d < 45.0 and not (spawned[key] and DoesEntityExist(spawned[key])) then
                local model = GetHashKey(p.ped or Config.PedModel)
                RequestModel(model)
                local t = 0
                while not HasModelLoaded(model) and t < 50 do Wait(20); t = t + 1 end
                local ped = CreatePed(4, model, p.coords.x, p.coords.y, p.coords.z - 1.0, p.coords.w, false, false)
                SetEntityInvincible(ped, true); FreezeEntityPosition(ped, true); SetBlockingOfNonTemporaryEvents(ped, true)
                spawned[key] = ped; SetModelAsNoLongerNeeded(model)
            elseif d >= 60.0 and spawned[key] and DoesEntityExist(spawned[key]) then
                DeletePed(spawned[key]); spawned[key] = nil
            end
        end
    end
end)

-- Proximity E prompt -> open the editor in that station's mode
CreateThread(function()
    while true do
        local wait = 700
        local coords = GetEntityCoords(PlayerPedId())
        for _, p in ipairs(points) do
            if #(coords - vector3(p.coords.x, p.coords.y, p.coords.z)) < Config.Distance then
                wait = 0
                BeginTextCommandDisplayHelp('STRING')
                AddTextComponentSubstringPlayerName('~INPUT_CONTEXT~ ' .. (strings()[p.i18n] or 'Appearance'))
                EndTextCommandDisplayHelp(0, false, true, -1)
                if IsControlJustReleased(0, 38) then OpenEditor(p.mode) end
                break
            end
        end
        Wait(wait)
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for _, ped in pairs(spawned) do if DoesEntityExist(ped) then DeletePed(ped) end end
end)
