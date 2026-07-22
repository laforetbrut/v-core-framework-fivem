-- v-vehicles | client/preview
-- A showroom "instance": the vehicle is created as a LOCAL (non-networked) entity at an
-- isolated point far from the map, and only the camera travels there. The player's ped
-- never moves, nothing is streamed to other players, and nothing can be interacted with
-- or crashed into — which is what makes it an instance rather than a spawned car.
--
-- Shared surface, used by v-garages today and the dealership next:
--   exports['v-vehicles']:OpenPreview(model, props)
--   exports['v-vehicles']:RotatePreview(dx)
--   exports['v-vehicles']:ZoomPreview(dz)
--   exports['v-vehicles']:ClosePreview()

local SHOWROOM = vector3(1200.0, -3200.0, -100.0)   -- under the map, nothing streams here

local veh, cam = nil, nil
local heading, dist, open = 0.0, 5.2, false

local function destroyVeh()
    if veh and DoesEntityExist(veh) then
        SetEntityAsMissionEntity(veh, true, true)
        DeleteVehicle(veh)
    end
    veh = nil
end

local function updateCam()
    if not cam or not veh or not DoesEntityExist(veh) then return end
    local c = GetEntityCoords(veh)
    local rad = math.rad(heading)
    SetCamCoord(cam, c.x + math.sin(rad) * dist, c.y - math.cos(rad) * dist, c.z + dist * 0.30)
    PointCamAtCoord(cam, c.x, c.y, c.z + 0.15)
end

local function closePreview()
    if not open then return end
    open = false
    RenderScriptCams(false, false, 0, true, false)
    if cam then DestroyCam(cam, false); cam = nil end
    destroyVeh()
    SetTimecycleModifier('default')
    ClearTimecycleModifier()
end

--- @param model string|number vehicle model
--- @param props table|nil stored properties to dress it with
--- @return boolean spawned
local function openPreview(model, props)
    closePreview()
    local hash = (type(model) == 'number') and model or joaat(tostring(model or ''))
    if not IsModelInCdimage(hash) or not IsModelAVehicle(hash) then return false end

    RequestModel(hash)
    local tries = 0
    while not HasModelLoaded(hash) and tries < 150 do Wait(20); tries = tries + 1 end
    if not HasModelLoaded(hash) then return false end

    -- `false, false` = not networked, not a mission entity: this car exists only here.
    veh = CreateVehicle(hash, SHOWROOM.x, SHOWROOM.y, SHOWROOM.z, 0.0, false, false)
    SetModelAsNoLongerNeeded(hash)
    if not veh or veh == 0 or not DoesEntityExist(veh) then return false end

    SetEntityCollision(veh, false, false)
    FreezeEntityPosition(veh, true)
    SetEntityInvincible(veh, true)
    SetVehicleDirtLevel(veh, 0.0)
    SetVehicleDoorsShut(veh, true)
    SetVehicleLights(veh, 2)
    if type(props) == 'table' then exports['v-vehicles']:ApplyProps(veh, props) end

    -- size the camera to the car so a bus and a bike both frame sensibly
    local min, max = GetModelDimensions(hash)
    local len = math.max(max.x - min.x, max.y - min.y, max.z - min.z)
    dist = math.max(3.4, len * 1.35)
    heading = 320.0

    cam = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA', 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 45.0, false, 0)
    SetCamActive(cam, true)
    RenderScriptCams(true, false, 0, true, false)
    updateCam()

    open = true
    -- a clean, evenly-lit look regardless of the in-world time of day
    SetTimecycleModifier('cinema')
    SetTimecycleModifierStrength(0.4)

    -- keep the showroom lit and the car turning smoothly while it is up
    CreateThread(function()
        while open do
            if veh and DoesEntityExist(veh) then
                SetEntityCoordsNoOffset(veh, SHOWROOM.x, SHOWROOM.y, SHOWROOM.z, false, false, false)
                SetEntityHeading(veh, 0.0)
                DrawLightWithRange(SHOWROOM.x, SHOWROOM.y, SHOWROOM.z + 3.0, 255, 190, 140, 12.0, 4.0)
                DrawLightWithRange(SHOWROOM.x + 4.0, SHOWROOM.y - 4.0, SHOWROOM.z + 2.0, 255, 122, 26, 10.0, 2.2)
            end
            Wait(0)
        end
    end)
    return true
end

exports('OpenPreview',   function(model, props) return openPreview(model, props) end)
exports('ClosePreview',  function() closePreview() end)
exports('IsPreviewOpen', function() return open end)

exports('RotatePreview', function(dx)
    heading = (heading + (tonumber(dx) or 0) * 0.45) % 360.0
    updateCam()
end)

exports('ZoomPreview', function(dz)
    dist = math.max(2.6, math.min(14.0, dist - (tonumber(dz) or 0) * 0.35))
    updateCam()
end)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then closePreview() end
end)
