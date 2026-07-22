-- v-3dsound | client
-- Plays what the server asked for, attenuated by this client's own distance.
--
-- Native sounds go straight to the engine, which does the 3D mix itself. Custom files go
-- through a small NUI page, because CEF has no notion of world space - so the distance is
-- turned into a volume here and handed over as a number.

local function num(v, d) return tonumber(v) or d or 0 end

--- Linear falloff with a flat head: full volume up close, silent at the edge. A squared
--- curve sounds more natural but makes anything past half the range effectively inaudible,
--- which is not what a caller asking for a 60 m alarm wants.
local function attenuate(dist, range)
    if range <= 0 then return 1.0 end
    local near = range * 0.15
    if dist <= near then return 1.0 end
    if dist >= range then return 0.0 end
    return 1.0 - ((dist - near) / (range - near))
end

RegisterNetEvent('v-3dsound:client:play', function(d)
    if type(d) ~= 'table' then return end

    -- Personal sounds have no position: they are the private counterpart of a world sound.
    if d.personal then
        if d.file then
            SendNUIMessage({ action = 'play', file = d.file,
                             volume = num(d.volume, 1.0) * num(d.master, 0.7) })
        elseif d.set and d.sound then
            PlaySoundFrontend(-1, d.sound, d.set, true)
        end
        return
    end

    local pos = vector3(num(d.x), num(d.y), num(d.z))

    -- An entity-attached sound follows the thing, not the place it was when the server
    -- sent the message - which for a moving car is a different place already.
    if d.netid then
        local ent = NetworkGetEntityFromNetworkId(d.netid)
        if ent and ent ~= 0 and DoesEntityExist(ent) then pos = GetEntityCoords(ent) end
    end

    local range = num(d.range, 15.0)

    if d.set and d.sound then
        -- The engine mixes native sounds in 3D itself; handing it the range is enough.
        PlaySoundFromCoord(-1, d.sound, pos.x, pos.y, pos.z, d.set, false, math.floor(range), false)
        return
    end

    if d.file then
        local dist = #(GetEntityCoords(PlayerPedId()) - pos)
        local vol = attenuate(dist, range) * num(d.volume, 1.0) * num(d.master, 0.7)
        if vol <= 0.01 then return end
        SendNUIMessage({ action = 'play', file = d.file, volume = vol })
    end
end)

-- Anything still playing when the resource stops would otherwise keep playing until the
-- player rejoins, because a NUI page outlives a Lua restart.
AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then SendNUIMessage({ action = 'stopAll' }) end
end)
