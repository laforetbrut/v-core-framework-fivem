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

-- Music diagnostics from the loading screen, echoed to the server console. Useful while a
-- server is being set up and noise afterwards, so the operator decides in the admin panel;
-- see vcore.lua. Capped per player so a loop in the page cannot flood the log.
local musicLines = {}

RegisterNetEvent('v-loadscreen:server:musicReport', function(line)
    local src = source
    if type(line) ~= 'string' then return end
    if not Loadscreen.musicDiagnostics() then return end

    local count = (musicLines[src] or 0) + 1
    musicLines[src] = count
    if count > Loadscreen.musicMaxLines() then return end

    -- The page composes this line, which means a modified client composes whatever it likes:
    -- this event can be triggered directly, without the loading screen being involved at all.
    -- Control characters are flattened before printing, because a newline inside the string
    -- turns one report into several lines that can be dressed up as another resource's log.
    local clean = line:gsub('%c', ' '):sub(1, 400)
    print(('%s | %s'):format(clean, GetPlayerName(src) or src))
end)

AddEventHandler('playerDropped', function()
    lastAsk[source] = nil
    musicLines[source] = nil
end)
