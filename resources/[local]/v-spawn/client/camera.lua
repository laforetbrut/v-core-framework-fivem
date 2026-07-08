-- v-spawn | creator camera (orbit around the ped, driven by the NUI)
local cam = nil
local state = { angle = 180.0, zone = 'body' }

local ZONES = {
    head = { z = 0.62, dist = 1.05 },
    body = { z = 0.15, dist = 2.40 },
    legs = { z = -0.65, dist = 1.90 },
}

local function update()
    if not cam then return end
    local coords = GetEntityCoords(PlayerPedId())
    local z = ZONES[state.zone] or ZONES.body
    local rad = math.rad(state.angle)
    SetCamCoord(cam, coords.x + math.sin(rad) * z.dist, coords.y + math.cos(rad) * z.dist, coords.z + z.z)
    PointCamAtCoord(cam, coords.x, coords.y, coords.z + z.z)
end

function CreatorCameraStart()
    state.angle, state.zone = 180.0, 'body'
    cam = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA', 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 45.0, false, 0)
    SetCamActive(cam, true)
    RenderScriptCams(true, false, 0, true, false)
    update()
end

function CreatorCameraRotate(delta)
    state.angle = (state.angle + delta) % 360.0
    update()
end

function CreatorCameraZone(zone)
    state.zone = zone
    update()
end

function CreatorCameraStop()
    RenderScriptCams(false, false, 0, true, false)
    if cam then DestroyCam(cam, false); cam = nil end
end
