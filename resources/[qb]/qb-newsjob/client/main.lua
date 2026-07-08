QBCore = exports['qb-core']:GetCoreObject({ 'Functions' })
PlayerJob = {}
CurrentPlate = {}

RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
    PlayerJob = QBCore.Functions.GetPlayerData().job
    if PlayerJob.name ~= 'reporter' then return end

    local blip = AddBlipForCoord(Config.Locations['vehicle'].coords.x, Config.Locations['vehicle'].coords.y, Config.Locations['vehicle'].coords.z)
    SetBlipSprite(blip, 225)
    SetBlipDisplay(blip, 4)
    SetBlipScale(blip, 0.6)
    SetBlipAsShortRange(blip, true)
    SetBlipColour(blip, 1)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(Lang:t('text.vehicle'))
    EndTextCommandSetBlipName(blip)
end)

RegisterNetEvent('QBCore:Client:OnPlayerUpdated', function(key, val)
    if key == 'job' then
        local JobInfo = val
        PlayerJob = JobInfo
        if PlayerJob.name ~= 'reporter' then return end

        local blip = AddBlipForCoord(Config.Locations['vehicle'].coords.x, Config.Locations['vehicle'].coords.y, Config.Locations['vehicle'].coords.z)
        SetBlipSprite(blip, 225)
        SetBlipDisplay(blip, 4)
        SetBlipScale(blip, 0.6)
        SetBlipAsShortRange(blip, true)
        SetBlipColour(blip, 1)
        BeginTextCommandSetBlipName('STRING')
        AddTextComponentSubstringPlayerName(Lang:t('text.vehicle'))
        EndTextCommandSetBlipName(blip)
    elseif key == 'all' then
        local JobInfo = val.job
        PlayerJob = JobInfo
        if PlayerJob.name ~= 'reporter' then return end

        local blip = AddBlipForCoord(Config.Locations['vehicle'].coords.x, Config.Locations['vehicle'].coords.y, Config.Locations['vehicle'].coords.z)
        SetBlipSprite(blip, 225)
        SetBlipDisplay(blip, 4)
        SetBlipScale(blip, 0.6)
        SetBlipAsShortRange(blip, true)
        SetBlipColour(blip, 1)
        BeginTextCommandSetBlipName('STRING')
        AddTextComponentSubstringPlayerName(Lang:t('text.vehicle'))
        EndTextCommandSetBlipName(blip)
    end
end)

local function DrawText3D(x, y, z, text)
    SetTextScale(0.35, 0.35)
    SetTextFont(4)
    SetTextProportional(1)
    SetTextColour(255, 255, 255, 215)
    BeginTextCommandDisplayText('STRING')
    SetTextCentre(true)
    AddTextComponentSubstringPlayerName(text)
    SetDrawOrigin(x, y, z, 0)
    EndTextCommandDisplayText(0.0, 0.0)
    local factor = (string.len(text)) / 370
    DrawRect(0.0, 0.0 + 0.0125, 0.017 + factor, 0.03, 0, 0, 0, 75)
    ClearDrawOrigin()
end

CreateThread(function()
    while true do
        Wait(3)
        if LocalPlayer.state.isLoggedIn then
            local inRange = false
            local pos = GetEntityCoords(PlayerPedId())
            if PlayerJob.name == 'reporter' then
                if #(pos - vector3(Config.Locations['vehicle'].coords.x, Config.Locations['vehicle'].coords.y, Config.Locations['vehicle'].coords.z)) < 10.0 then
                    inRange = true
                    DrawMarker(2, Config.Locations['vehicle'].coords.x, Config.Locations['vehicle'].coords.y, Config.Locations['vehicle'].coords.z, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.3, 0.2, 0.15, 200, 200, 200, 222, false, false, false, true, false, false, false)
                    if #(pos - vector3(Config.Locations['vehicle'].coords.x, Config.Locations['vehicle'].coords.y, Config.Locations['vehicle'].coords.z)) < 1.5 then
                        if IsPedInAnyVehicle(PlayerPedId(), false) then
                            DrawText3D(Config.Locations['vehicle'].coords.x, Config.Locations['vehicle'].coords.y, Config.Locations['vehicle'].coords.z, Lang:t('text.store_vehicle'))
                        else
                            DrawText3D(Config.Locations['vehicle'].coords.x, Config.Locations['vehicle'].coords.y, Config.Locations['vehicle'].coords.z, Lang:t('text.vehicles'))
                        end
                        if IsControlJustReleased(0, 38) then
                            if IsPedInAnyVehicle(PlayerPedId(), false) then
                                StoreCurrentVehicle()
                            else
                                MenuGarage('vehicle')
                            end
                        end
                    end
                elseif #(pos - vector3(Config.Locations['heli'].coords.x, Config.Locations['heli'].coords.y, Config.Locations['heli'].coords.z)) < 5.0 then
                    inRange = true
                    DrawMarker(2, Config.Locations['heli'].coords.x, Config.Locations['heli'].coords.y, Config.Locations['heli'].coords.z, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.3, 0.2, 0.15, 200, 200, 200, 222, false, false, false, true, false, false, false)
                    if #(pos - vector3(Config.Locations['heli'].coords.x, Config.Locations['heli'].coords.y, Config.Locations['heli'].coords.z)) < 1.5 then
                        if IsPedInAnyVehicle(PlayerPedId(), false) then
                            DrawText3D(Config.Locations['heli'].coords.x, Config.Locations['heli'].coords.y, Config.Locations['heli'].coords.z, Lang:t('text.store_helicopters'))
                        else
                            DrawText3D(Config.Locations['heli'].coords.x, Config.Locations['heli'].coords.y, Config.Locations['heli'].coords.z, Lang:t('text.helicopters'))
                        end
                        if IsControlJustReleased(0, 38) then
                            if IsPedInAnyVehicle(PlayerPedId(), false) then
                                StoreCurrentVehicle()
                            else
                                MenuGarage('heli')
                            end
                        end
                    end
                end
                if not inRange then
                    Wait(2500)
                end
            else
                Wait(2500)
            end
        else
            Wait(2500)
        end
    end
end)

CreateThread(function()
    while true do
        Wait(1)
        local inRange = false
        if LocalPlayer.state.isLoggedIn then
            local pos = GetEntityCoords(PlayerPedId())
            if #(pos - vector3(Config.Locations['main'].coords.x, Config.Locations['main'].coords.y, Config.Locations['main'].coords.z)) < 1.5 or #(pos - vector3(Config.Locations['inside'].coords.x, Config.Locations['inside'].coords.y, Config.Locations['inside'].coords.z)) < 1.5 then
                inRange = true
                if #(pos - vector3(Config.Locations['main'].coords.x, Config.Locations['main'].coords.y, Config.Locations['main'].coords.z)) < 1.5 then
                    DrawText3D(Config.Locations['main'].coords.x, Config.Locations['main'].coords.y, Config.Locations['main'].coords.z, Lang:t('text.enter'))
                    if IsControlJustReleased(0, 38) then
                        DoScreenFadeOut(500)
                        while not IsScreenFadedOut() do
                            Wait(10)
                        end

                        SetEntityCoords(PlayerPedId(), Config.Locations['inside'].coords.x, Config.Locations['inside'].coords.y, Config.Locations['inside'].coords.z, 0, 0, 0, false)
                        SetEntityHeading(PlayerPedId(), Config.Locations['inside'].coords.w)

                        Wait(100)

                        DoScreenFadeIn(1000)
                    end
                elseif #(pos - vector3(Config.Locations['inside'].coords.x, Config.Locations['inside'].coords.y, Config.Locations['inside'].coords.z)) < 1.5 then
                    DrawText3D(Config.Locations['inside'].coords.x, Config.Locations['inside'].coords.y, Config.Locations['inside'].coords.z, Lang:t('text.go_outside'))
                    if IsControlJustReleased(0, 38) then
                        DoScreenFadeOut(500)
                        while not IsScreenFadedOut() do
                            Wait(10)
                        end

                        SetEntityCoords(PlayerPedId(), Config.Locations['outside'].coords.x, Config.Locations['outside'].coords.y, Config.Locations['outside'].coords.z, 0, 0, 0, false)
                        SetEntityHeading(PlayerPedId(), Config.Locations['outside'].coords.w)

                        Wait(100)

                        DoScreenFadeIn(1000)
                    end
                end
            end
        end
        if not inRange then
            Wait(2500)
        end
    end
end)
