-- v-rentals | client
-- Marker + blip per hire point, the counter NUI, and the return prompt. Every gate here
-- is cosmetic: the server re-derives proximity, price, licence and ownership.

local Points = {}
local blips = {}
local open = false
local current = nil          -- the point the NUI is showing

local function strings()
    return Locales[(LocalPlayer.state and LocalPlayer.state.lang) or 'fr'] or Locales.fr or {}
end
local function L(k) return strings()[k] or k end

-- ── Blips ──────────────────────────────────────────────────────
local function clearBlips()
    for _, b in ipairs(blips) do if DoesBlipExist(b) then RemoveBlip(b) end end
    blips = {}
end

local function buildBlips()
    clearBlips()
    if V.SettingBool('blips', true) == false then return end
    for _, p in ipairs(Points) do
        if p.blip ~= false and p.enabled ~= false then
            local b = AddBlipForCoord(p.x + 0.0, p.y + 0.0, p.z + 0.0)
            SetBlipSprite(b, Config.Blip)
            SetBlipColour(b, Config.BlipColor)
            SetBlipScale(b, 0.7); SetBlipAsShortRange(b, true)
            BeginTextCommandSetBlipName('STRING')
            AddTextComponentSubstringPlayerName(p.label or L('rent.blip'))
            EndTextCommandSetBlipName(b)
            blips[#blips + 1] = b
        end
    end
end

RegisterNetEvent('v-rentals:client:points', function(list)
    Points = list or {}
    buildBlips()
end)

V.Ready(function()
    Wait(1200)
    TriggerServerEvent('v-rentals:server:request')
end)

-- ── NUI ────────────────────────────────────────────────────────
local function close()
    if not open then return end
    open = false; current = nil
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
    if GetResourceState('v-core') == 'started' then
        pcall(function() exports['v-core']:MenuClosed('v-rentals') end)
    end
end

local function openAt(point)
    if open then return end
    V.Request('v-rentals:open', function(data)
        if not data or data.error then
            if data and data.error == 'far' then V.Notify(L('rent.err_far'), 'error') end
            return
        end
        open, current = true, point
        SetNuiFocus(true, true)
        if GetResourceState('v-core') == 'started' then
            pcall(function() exports['v-core']:MenuOpened('v-rentals') end)
        end
        SendNUIMessage({ action = 'open', data = data, strings = strings() })
    end, point.id)
end

-- ── Markers + prompts ──────────────────────────────────────────
CreateThread(function()
    while true do
        local wait = 900
        if not open and #Points > 0 then
            local ped = PlayerPedId()
            local coords = GetEntityCoords(ped)
            local range = tonumber(V.Setting('distance', Config.Distance)) or Config.Distance

            for _, p in ipairs(Points) do
                if p.enabled ~= false then
                    local d = #(coords - vector3(p.x + 0.0, p.y + 0.0, p.z + 0.0))
                    if d < 25.0 then
                        wait = 0
                        DrawMarker(Config.Marker.type, p.x + 0.0, p.y + 0.0, p.z - 0.95,
                            0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
                            Config.Marker.size, Config.Marker.size, Config.Marker.size,
                            Config.Marker.r, Config.Marker.g, Config.Marker.b, Config.Marker.a,
                            false, false, 2, false, nil, nil, false)
                        if d < range then
                            local inVeh = IsPedInAnyVehicle(ped, false)
                            BeginTextCommandDisplayHelp('STRING')
                            AddTextComponentSubstringPlayerName('~INPUT_CONTEXT~ ' ..
                                (inVeh and L('rent.help_return') or L('rent.help_open')))
                            EndTextCommandDisplayHelp(0, false, true, -1)
                            if IsControlJustReleased(0, 38) then    -- E
                                if inVeh then
                                    local veh = GetVehiclePedIsIn(ped, false)
                                    V.Request('v-rentals:returnCar', function(res)
                                        if res and res.ok then
                                            V.Notify(res.refund > 0
                                                and (L('rent.returned')):format(res.refund)
                                                or L('rent.returned_late'),
                                                res.refund > 0 and 'success' or 'warning')
                                        elseif res and res.error then
                                            V.Notify(L('rent.err_' .. res.error), 'error')
                                        end
                                    end, { point = p.id, netid = VehToNet(veh) })
                                else
                                    openAt(p)
                                end
                            end
                        end
                    end
                end
            end
        end
        Wait(wait)
    end
end)

-- ── NUI callbacks ──────────────────────────────────────────────
RegisterNUICallback('close', function(_, cb) close(); cb('ok') end)

RegisterNUICallback('hire', function(data, cb)
    cb('ok')
    if not current then return end
    local point = current
    close()
    V.Request('v-rentals:hire', function(res)
        if not res or res.error then
            V.Notify(L('rent.err_' .. ((res and res.error) or 'x')), 'error')
            return
        end
        V.Notify((L('rent.hired')):format(res.plate, res.minutes), 'success')
        -- Put the player in the driver's seat: they paid for it, and walking round the
        -- car to find it unlocked is not the experience.
        local veh = NetToVeh(res.netid)
        local tries = 0
        while (not veh or veh == 0 or not DoesEntityExist(veh)) and tries < 60 do
            Wait(50); veh = NetToVeh(res.netid); tries = tries + 1
        end
        if veh and veh ~= 0 and DoesEntityExist(veh) then
            SetVehicleNumberPlateText(veh, res.plate)
            TaskWarpPedIntoVehicle(PlayerPedId(), veh, -1)
        end
    end, { point = point.id, model = data.model })
end)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then
        clearBlips()
        if open then SetNuiFocus(false, false) end
    end
end)

-- ── Theme ──────────────────────────────────────────────────────
local function pushTheme()
    if GetResourceState('v-ui') ~= 'started' then return end
    pcall(function() exports['v-ui']:Push() end)
end
AddEventHandler('v-ui:client:themeChanged', function() pushTheme() end)
CreateThread(function() Wait(4000); pushTheme() end)
