--[[
    v-loadscreen - client
    author: doc, vyrriox

    The loading screen itself is HTML. This script does three things:
      1. reads the runtime block of config.js, handed over by the page at boot
      2. feeds the page the live player count
      3. decides when the screen goes away, with a safety net so nobody is ever
         left staring at a black screen
]]

local runtime = {
    -- fallbacks only. config.js is the source of truth; these apply just for
    -- the few milliseconds before the page reports in, or if it never does.
    manualShutdown = false,
    shutdownDelay = 1.5,
    minimumDisplayTime = 6.0,
    enterButton = false,
    failsafeTimeout = 180.0,
    wantsServerInfo = true,
}

local startedAt = GetGameTimer()
local uiReady = false
local musicDebug = false
local shutdownDone = false   -- we called the shutdown ourselves
local screenGone = false     -- the screen is not displayed any more, by whoever closed it
local playerLoaded = false   -- v-core says the character is in the world
local enterPressed = false
local lastBeat = 0

local function sendToUi(payload)
    SendLoadingScreenMessage(json.encode(payload))
end

local function shutdown(full)
    if shutdownDone then return end
    shutdownDone = true
    screenGone = true
    if full then
        ShutdownLoadingScreen()
    end
    ShutdownLoadingScreenNui()
end

-- config.js is the source of truth, but a loading screen cannot be relied on to
-- reach Lua through an NUI callback: on some builds those never arrive. Read
-- the file straight off disk so the runtime block applies either way. Anything
-- that fails to parse simply leaves the fallback above in place.
local function parseRuntimeConfig()
    local raw = LoadResourceFile(GetCurrentResourceName(), 'config.js')
    if not raw then return end

    -- drop comments first, so their prose cannot be mistaken for a setting
    raw = raw:gsub('/%*.-%*/', ''):gsub('//[^\n]*', '')

    local block = raw:match('runtime%s*:%s*%{(.-)%}')
    if block then
        for key, value in block:gmatch('([%a][%w_]*)%s*:%s*([%w%.%-]+)') do
            local current = runtime[key]
            if type(current) == 'boolean' and (value == 'true' or value == 'false') then
                runtime[key] = (value == 'true')
            elseif type(current) == 'number' and tonumber(value) then
                runtime[key] = tonumber(value)
            end
        end
    end

    local wants = raw:match('showPlayerCount%s*:%s*(%a+)')
    if wants == 'true' or wants == 'false' then
        runtime.wantsServerInfo = (wants == 'true')
    end

    musicDebug = raw:match('debug%s*:%s*(%a+)') == 'true'
end

parseRuntimeConfig()

-- No native answers "is the loading screen still up", and two resources close it
-- here without telling anyone: qb-core in its OnPlayerLoaded handler, and
-- qb-multicharacter as soon as the character menu opens. So watch for the things
-- that can only be true once one of them has taken over. Any single one is
-- enough, and none of them depends on the page being able to call back.
local function takenOver()
    -- the page heartbeats every second; the beats stopping means it is gone.
    -- Only meaningful if the page proved it can call back at all.
    if uiReady and lastBeat > 0 and GetGameTimer() - lastBeat > 5000 then
        return true
    end
    -- another resource has claimed NUI focus, which a loading screen never does
    if IsNuiFocused() then return true end
    -- v-core has finished putting the character in the world
    if playerLoaded then return true end
    return false
end

-- v-core fires this once the character is loaded and spawned. It is the framework's
-- own "you are in the world now" signal, and the most direct one there is.
AddEventHandler('v-core:client:onPlayerLoaded', function()
    playerLoaded = true
    screenGone = true
end)

AddEventHandler('playerSpawned', function()
    screenGone = true
end)

-- The page hands over the runtime block from config.js as soon as it boots.
RegisterNUICallback('uiReady', function(data, cb)
    if type(data) == 'table' then
        for key, value in pairs(data) do
            if runtime[key] ~= nil and type(value) == type(runtime[key]) then
                runtime[key] = value
            end
        end
    end
    uiReady = true
    cb({ ok = true })
end)

RegisterNUICallback('enter', function(_, cb)
    enterPressed = true
    cb({ ok = true })
end)

-- Heartbeat from the page. Its absence is what tells us the screen has been
-- closed by something else.
RegisterNUICallback('alive', function(_, cb)
    lastBeat = GetGameTimer()
    cb({ ok = true })
end)

-- The loading screen reports here about the music. Forwarded to the server as
-- well as the client console, because the server console is the one an owner
-- actually has open while testing.
RegisterNUICallback('musicIssue', function(data, cb)
    if type(data) == 'table' then
        local line = ('[v-loadscreen] music %s: %s | %s | %s | %s'):format(
            tostring(data.kind), tostring(data.detail), tostring(data.src),
            tostring(data.state), tostring(data.support))
        print(line)
        TriggerServerEvent('v-loadscreen:server:musicReport', line)
    end
    cb({ ok = true })
end)

RegisterNetEvent('v-loadscreen:client:info', function(info)
    if screenGone or type(info) ~= 'table' then return end
    info.action = 'serverInfo'
    sendToUi(info)
end)

-- Watches for the screen being closed by another resource, so every other
-- thread here can stand down instead of running for the whole session. Only
-- starts once the session is up: before that, none of these signals means
-- anything, and NUI focus in particular could be a false positive.
CreateThread(function()
    while not NetworkIsSessionStarted() do
        Wait(250)
    end
    while not screenGone do
        Wait(500)
        if takenOver() then
            screenGone = true
        end
    end
end)

-- Live player count. Kept refreshing while the screen is up, so the number the
-- player reads is the number that is actually connected.
CreateThread(function()
    local deadline = GetGameTimer() + 8000
    while not uiReady and GetGameTimer() < deadline do
        Wait(150)
    end
    if not runtime.wantsServerInfo then return end

    while not screenGone do
        TriggerServerEvent('v-loadscreen:server:requestInfo')
        for _ = 1, 20 do
            if screenGone then return end
            Wait(500)
        end
    end
end)

-- Closing sequence.
CreateThread(function()
    while not NetworkIsSessionStarted() do
        Wait(200)
    end
    local sessionAt = GetGameTimer()
    sendToUi({ action = 'gameReady' })

    if runtime.manualShutdown then
        local minimum = (tonumber(runtime.minimumDisplayTime) or 0) * 1000
        while GetGameTimer() - startedAt < minimum do
            Wait(100)
        end

        if runtime.enterButton then
            -- The click reports through an NUI callback. If the page cannot
            -- reach Lua on this build, that click never arrives, and waiting
            -- for it would leave the player staring at a button that does
            -- nothing. Give it ten seconds, then carry on without it.
            local waited = 0
            while not enterPressed do
                Wait(100)
                waited = waited + 100
                if not uiReady and waited >= 10000 then
                    print('[v-loadscreen] the enter button cannot report back on this build, closing without it')
                    break
                end
            end
            Wait(700) -- let the page play its fade out
        else
            -- Hold the screen until the world is actually ready rather than closing on
            -- a blind timer: any "the player is in" signal (v-core onPlayerLoaded,
            -- playerSpawned, or the takeover watcher) flips screenGone. The failsafe
            -- ceiling guarantees a stalled session still lets go of the player.
            local ceiling = GetGameTimer() + math.max(1, tonumber(runtime.failsafeTimeout) or 180) * 1000
            while not screenGone and GetGameTimer() < ceiling do
                Wait(100)
            end
            Wait(math.floor((tonumber(runtime.shutdownDelay) or 0) * 1000))
            sendToUi({ action = 'fadeOut' })
            Wait(750)
        end

        shutdown(true)
        return
    end

    -- Not our job to close it: qb-multicharacter (or whatever else the server
    -- runs) calls ShutdownLoadingScreenNui when it is ready. We only step in if
    -- that never happens, so a broken resource cannot strand the player.
    local failsafe = tonumber(runtime.failsafeTimeout) or 0
    if failsafe <= 0 then return end

    while GetGameTimer() - sessionAt < failsafe * 1000 do
        -- somebody else closed it, which is the normal path: stand down quietly
        if screenGone then return end
        Wait(500)
    end

    print(('[v-loadscreen] failsafe: nothing closed the loading screen %ds after the session started, closing it now (page callbacks: %s)')
        :format(failsafe, uiReady and 'yes' or 'no'))
    shutdown(false)
end)

-- Only worth saying while somebody is actually waiting on those reports: it
-- explains why an empty console is not the same as nothing going wrong. Silent
-- otherwise, since nothing here depends on that channel any more.
CreateThread(function()
    if not musicDebug then return end
    while not NetworkIsSessionStarted() do
        Wait(250)
    end
    Wait(15000)
    if not uiReady then
        print('[v-loadscreen] music debug is on, but the loading screen cannot call back into Lua on this build: its reports appear in the client console (F8), not here')
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then
        shutdown(false)
    end
end)
