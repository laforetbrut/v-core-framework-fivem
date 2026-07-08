-- v-core | client-side callback system
VCore = VCore or {}
VCore.PendingCallbacks = {}

local requestId = 0

--- Request data from the server and receive it in `cb`.
---   Core.TriggerCallback('v-core:getPlayerData', function(data) ... end)
function VCore.TriggerCallback(name, cb, ...)
    requestId = requestId + 1
    VCore.PendingCallbacks[requestId] = cb
    TriggerServerEvent('v-core:server:callback', name, requestId, ...)
end

RegisterNetEvent('v-core:client:callback', function(id, ...)
    local cb = VCore.PendingCallbacks[id]
    if cb then
        cb(...)
        VCore.PendingCallbacks[id] = nil
    end
end)
