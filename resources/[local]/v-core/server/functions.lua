-- v-core | server functions
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

--- Return an array of every loaded player object.
function VCore.GetPlayers()
    local list = {}
    for _, player in pairs(VCore.Players) do
        list[#list + 1] = player
    end
    return list
end

--- Send a notification to a client from the server.
function VCore.Notify(source, message)
    TriggerClientEvent('v-core:client:notify', source, message)
end
