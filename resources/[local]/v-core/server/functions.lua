-- v-core | server helpers
VCore = VCore or {}
VCore.Players = {}   -- [source] = player object

--- Resolve a player's FiveM license identifier.
function VCore.GetLicense(source)
    for _, id in ipairs(GetPlayerIdentifiers(source)) do
        if id:sub(1, 8) == 'license:' then
            return id
        end
    end
    return nil
end

--- Return the loaded player object for a source, or nil.
function VCore.GetPlayer(source)
    return VCore.Players[source]
end

--- Return the loaded player object for a citizen id, or nil.
function VCore.GetPlayerByCitizenId(citizenid)
    for _, player in pairs(VCore.Players) do
        if player.citizenid == citizenid then
            return player
        end
    end
    return nil
end

--- Return an array of every loaded player object.
function VCore.GetPlayers()
    local list = {}
    for _, player in pairs(VCore.Players) do
        list[#list + 1] = player
    end
    return list
end

--- Send a notification to a client from the server.
function VCore.Notify(source, message, kind, duration)
    TriggerClientEvent('v-core:client:notify', source, message, kind, duration)
end

--- Generate a unique-ish citizen id, e.g. "V4KD9P2A".
function VCore.GenerateCitizenId()
    local charset = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'
    local id = 'V'
    for _ = 1, 7 do
        local n = math.random(1, #charset)
        id = id .. charset:sub(n, n)
    end
    return id
end
