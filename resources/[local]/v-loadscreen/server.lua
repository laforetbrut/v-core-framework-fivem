--[[
    v-loadscreen - server
    author: doc, vyrriox

    Answers the loading screen's request for the live player count. That is all
    it does; nothing here touches gameplay.
]]

local lastAsk = {}
local COOLDOWN = 4000 -- ms, per player

RegisterNetEvent('v-loadscreen:server:requestInfo', function()
    local src = source
    local now = GetGameTimer()

    if lastAsk[src] and now - lastAsk[src] < COOLDOWN then return end
    lastAsk[src] = now

    TriggerClientEvent('v-loadscreen:client:info', src, {
        players = #GetPlayers(),
        maxPlayers = GetConvarInt('sv_maxclients', 48),
    })
end)

-- Music diagnostics from the loading screen, echoed to the server console.
-- Capped per player so a loop in the page cannot flood the log.
local musicLines = {}
local MAX_LINES = 40

RegisterNetEvent('v-loadscreen:server:musicReport', function(line)
    local src = source
    if type(line) ~= 'string' then return end

    local count = (musicLines[src] or 0) + 1
    musicLines[src] = count
    if count > MAX_LINES then return end

    print(('%s | %s'):format(line:sub(1, 400), GetPlayerName(src) or src))
end)

AddEventHandler('playerDropped', function()
    lastAsk[source] = nil
    musicLines[source] = nil
end)
