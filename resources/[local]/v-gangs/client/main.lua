-- v-gangs | client
-- Draws the turfs on the map. Nothing is decided here: capture is entirely server-side,
-- and this file only renders what the server last told it.

local Turfs, State = {}, {}
local blips, radii = {}, {}
local cfg = { blips = true, colors = {}, neutral = 0, blip = { sprite = 84, alpha = 110, scale = 0.9 } }

local function strings()
    return Locales[(LocalPlayer.state and LocalPlayer.state.lang) or 'fr'] or Locales.fr or {}
end
local function L(k) return strings()[k] or k end

local function clear()
    for _, b in ipairs(blips) do if DoesBlipExist(b) then RemoveBlip(b) end end
    for _, b in ipairs(radii) do if DoesBlipExist(b) then RemoveBlip(b) end end
    blips, radii = {}, {}
end

local function colorFor(owner)
    if not owner then return cfg.neutral or 0 end
    return cfg.colors[owner] or cfg.neutral or 0
end

local function build()
    clear()
    if not cfg.blips then return end

    for _, tf in ipairs(Turfs) do
        if tf.enabled ~= false and tf.blip ~= false then
            local st = State[tf.id] or {}
            local col = colorFor(st.owner)

            -- The radius blip is the territory itself; the icon on top is what you can
            -- click for the name and who holds it.
            local r = AddBlipForRadius(tf.x + 0.0, tf.y + 0.0, tf.z + 0.0, (tf.radius or 90.0) + 0.0)
            SetBlipHighDetail(r, true)
            SetBlipColour(r, col)
            SetBlipAlpha(r, cfg.blip.alpha or 110)
            radii[#radii + 1] = r

            local b = AddBlipForCoord(tf.x + 0.0, tf.y + 0.0, tf.z + 0.0)
            SetBlipSprite(b, cfg.blip.sprite or 84)
            SetBlipColour(b, col)
            SetBlipScale(b, cfg.blip.scale or 0.9)
            SetBlipAsShortRange(b, true)

            local who = st.owner and (st.ownerLabel or st.owner) or L('gang.nobody')
            local name = ('%s — %s (%d%%)'):format(tf.label or tf.id, who, math.floor(st.influence or 0))
            BeginTextCommandSetBlipName('STRING')
            AddTextComponentSubstringPlayerName(name)
            EndTextCommandSetBlipName(b)
            blips[#blips + 1] = b
        end
    end
end

RegisterNetEvent('v-gangs:client:state', function(payload)
    if type(payload) ~= 'table' then return end
    Turfs = payload.turfs or {}
    State = payload.state or {}
    cfg.blips   = payload.blips ~= false
    cfg.colors  = payload.colors or {}
    cfg.neutral = payload.neutral or 0
    cfg.blip    = payload.blip or cfg.blip
    build()
end)

V.Ready(function()
    Wait(1500)
    TriggerServerEvent('v-gangs:server:request')
end)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then clear() end
end)

-- The turf a player is standing in, for any script that wants to gate on territory
-- without asking the server. The server still re-derives it before acting on anything.
exports('LocalTurf', function()
    local c = GetEntityCoords(PlayerPedId())
    for _, tf in ipairs(Turfs) do
        if tf.enabled ~= false
           and #(c - vector3(tf.x + 0.0, tf.y + 0.0, tf.z + 0.0)) <= (tf.radius or 90.0) then
            local st = State[tf.id] or {}
            return tf.id, st.owner
        end
    end
    return nil
end)
