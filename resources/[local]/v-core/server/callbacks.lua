-- v-core | server-side callback system
-- Lets clients request data from the server and get a response, e.g.:
--   Core.TriggerCallback('v-core:getBalance', function(money) ... end)
VCore = VCore or {}
VCore.ServerCallbacks = {}

--- Register a server callback. Handler signature: (source, resolve, ...args).
function VCore.RegisterCallback(name, handler)
    VCore.ServerCallbacks[name] = handler
end

RegisterNetEvent('v-core:server:callback', function(name, requestId, ...)
    local src = source
    local handler = VCore.ServerCallbacks[name]
    if not handler then
        VCore.Debug(('unknown server callback: %s'):format(name))
        return
    end
    handler(src, function(...)
        TriggerClientEvent('v-core:client:callback', src, requestId, ...)
    end, ...)
end)
