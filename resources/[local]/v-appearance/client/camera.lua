-- v-appearance | editor camera (front orbit, drag to rotate the ped)
local cam = nil
local heading = 0.0     -- degrees around the ped
local zone = 'head'     -- head | body | full

local ZONES = {
    head = { z = 0.62, dist = 0.9,  fov = 24.0 },
    body = { z = 0.20, dist = 1.7,  fov = 34.0 },
    full = { z = 0.10, dist = 2.4,  fov = 42.0 },
}

local function place()
    if not cam then return end
    local ped = PlayerPedId()
    local c = GetEntityCoords(ped)
    local z = ZONES[zone] or ZONES.head
    local rad = math.rad(GetEntityHeading(ped) + heading)
    SetCamCoord(cam, c.x - math.sin(rad) * z.dist, c.y + math.cos(rad) * z.dist, c.z + z.z)
    PointCamAtCoord(cam, c.x, c.y, c.z + z.z)
    SetCamFov(cam, z.fov)
end

function EditorCamStart()
    cam = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA', 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 30.0, false, 0)
    SetCamActive(cam, true)
    RenderScriptCams(true, false, 0, true, false)
    heading = 0.0; zone = 'head'
    place()
end

function EditorCamStop()
    RenderScriptCams(false, false, 0, true, false)
    if cam then DestroyCam(cam, false); cam = nil end
end

function EditorCamOrbit(dx)
    heading = (heading + (dx or 0) * 0.4) % 360.0
    place()
end

function EditorCamZone(z)
    if ZONES[z] then zone = z; place() end
end
