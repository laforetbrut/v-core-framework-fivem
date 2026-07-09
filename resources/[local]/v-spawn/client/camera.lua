-- v-spawn | creator camera — free orbit driven by the mouse (drag + wheel)
local cam = nil
local state = { heading = 180.0, pitch = 0.0, dist = 2.2, zone = 'body' }

local ZONES = {
    head = { z = 0.62, dist = 1.0 },
    body = { z = 0.10, dist = 2.2 },
    legs = { z = -0.65, dist = 1.9 },
}

local function update()
    if not cam then return end
    local coords = GetEntityCoords(PlayerPedId())
    local z = ZONES[state.zone] or ZONES.body
    local targetZ = coords.z + z.z
    local yaw = math.rad(state.heading)
    local pitch = math.rad(state.pitch)
    local horiz = state.dist * math.cos(pitch)
    SetCamCoord(cam,
        coords.x + math.sin(yaw) * horiz,
        coords.y + math.cos(yaw) * horiz,
        targetZ + state.dist * math.sin(pitch))
    PointCamAtCoord(cam, coords.x, coords.y, targetZ)
end

function CreatorCameraStart()
    state.heading, state.pitch, state.dist, state.zone = 180.0, 0.0, 2.2, 'body'
    cam = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA', 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 42.0, false, 0)
    SetCamActive(cam, true)
    RenderScriptCams(true, false, 0, true, false)
    update()
end

-- Mouse drag: horizontal = orbit, vertical = pitch.
function CreatorCameraOrbit(dx, dy)
    state.heading = (state.heading + (dx or 0) * 0.4) % 360.0
    state.pitch = math.max(-45.0, math.min(45.0, state.pitch - (dy or 0) * 0.3))
    update()
end

-- Mouse wheel: zoom.
function CreatorCameraZoom(delta)
    state.dist = math.max(0.65, math.min(4.2, state.dist - (delta or 0) * 0.22))
    update()
end

-- Quick focus zones.
function CreatorCameraZone(zone)
    state.zone = zone
    state.dist = (ZONES[zone] or ZONES.body).dist
    update()
end

function CreatorCameraStop()
    RenderScriptCams(false, false, 0, true, false)
    if cam then DestroyCam(cam, false); cam = nil end
end
