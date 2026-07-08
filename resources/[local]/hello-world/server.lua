-- hello-world | server
-- Minimal vanilla FiveM server script. Copy this folder to start a new resource.

-- Greet players as they connect.
AddEventHandler('playerConnecting', function(name, _setKickReason, _deferrals)
    print(('[hello-world] %s is connecting...'):format(name))
end)

-- Answer the client's player-count request.
RegisterNetEvent('hello-world:requestPlayerCount', function()
    local src = source
    TriggerClientEvent('hello-world:playerCount', src, #GetPlayers())
end)

-- /ping — server console command.
RegisterCommand('ping', function(source, _args, _raw)
    print(('[hello-world] pong (from source %s)'):format(source))
end, true)

print('^2[hello-world]^7 server loaded.')
