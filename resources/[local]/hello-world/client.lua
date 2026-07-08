-- hello-world | client
-- Minimal vanilla FiveM client script. Copy this folder to start a new resource.

-- /hello — native notification above the minimap.
RegisterCommand('hello', function()
    SetNotificationTextEntry('STRING')
    AddTextComponentSubstringPlayerName('Hello from the vanilla dev server!')
    DrawNotification(false, true)
end, false)

-- /coords — print current position to chat and the F8 console.
RegisterCommand('coords', function()
    local c = GetEntityCoords(PlayerPedId())
    local msg = ('coords: %.2f, %.2f, %.2f'):format(c.x, c.y, c.z)
    TriggerEvent('chat:addMessage', { args = { '^2[dev]^7', msg } })
    print(msg)
end, false)

-- /players — client -> server -> client round-trip example.
RegisterCommand('players', function()
    TriggerServerEvent('hello-world:requestPlayerCount')
end, false)

RegisterNetEvent('hello-world:playerCount', function(count)
    TriggerEvent('chat:addMessage', { args = { '^5[dev]^7', ('players online: %d'):format(count) } })
end)

print('[hello-world] client loaded — try /hello, /coords, /players')
