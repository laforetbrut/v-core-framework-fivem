-- v-phone | client
--
-- The bridge between the iFruit page and the modules it is a view of.
--
-- **App data is fetched from the module that owns it, not from v-phone.** The bank app
-- calls `v-banking:getData`, the garage app calls `v-vehicles:myVehicles`, the wallet app
-- calls `v-licenses:mine`. Routing those through the phone server would put a second copy
-- of each module's rules in the phone, and a second copy is a second answer.
--
-- The phone does **no audio**: a call hands both ends to `v-voice`, which owns the Mumble
-- channel. The phone only decides who is talking to whom, and the server decides that.

local isOpen  = false
local myNumber = nil
local call    = nil          -- { id, state = 'out'|'in'|'active', number }
local power   = { battery = 100, charging = false, signal = 4 }

local function strings()
    return Locales[(LocalPlayer.state and LocalPlayer.state.lang) or 'fr'] or Locales.fr or {}
end
local function L(k) return strings()[k] or k end

local function voice() return GetResourceState('v-voice') == 'started' end

-- ══════════════════════════════════════════════════════════════
-- Open / close
-- ══════════════════════════════════════════════════════════════
local function openPhone()
    if isOpen then return end
    if exports['v-core']:IsAnyMenuOpen() then return end

    V.Request('v-phone:open', function(state)
        if not state or state.error then
            V.Notify(L('ph.err_' .. ((state and state.error) or 'x')), 'error')
            return
        end
        isOpen = true
        myNumber = state.number
        SetNuiFocus(true, true)          -- focus is per-resource: only the page owner may take it
        exports['v-core']:MenuOpened('v-phone')
        -- The screen is what drains a phone, so the server has to know it is on.
        TriggerServerEvent('v-phone:server:screen', true)
        state.action  = 'open'
        state.strings = strings()
        state.call    = call
        state.power   = power
        SendNUIMessage(state)
    end)
end

local function closePhone()
    if not isOpen then return end
    isOpen = false
    SetNuiFocus(false, false)
    exports['v-core']:MenuClosed('v-phone')
    TriggerServerEvent('v-phone:server:screen', false)
    SendNUIMessage({ action = 'close' })
end

RegisterCommand('vphone', function() if isOpen then closePhone() else openPhone() end end, false)
RegisterKeyMapping('vphone', 'Open the phone', 'keyboard', Config.Key or 'F1')

-- ══════════════════════════════════════════════════════════════
-- App data
-- ══════════════════════════════════════════════════════════════
-- One table, so adding an app is one row rather than a branch. `res` is the module that
-- must be running for the app to have anything to say.
local APP_SOURCE = {
    bank   = { res = 'v-banking',  callback = 'v-banking:getData' },
    garage = { res = 'v-vehicles', callback = 'v-vehicles:myVehicles' },
    wallet = { res = 'v-licenses', callback = 'v-licenses:mine' },
    jobs     = { res = 'v-cityhall', callback = 'v-phone:jobs' },
    music    = { res = 'v-music',    callback = 'v-music:list' },
    property = { res = 'v-housing',  callback = 'v-housing:mine' },
}

RegisterNUICallback('app', function(data, cb)
    local id  = data and tostring(data.app or '')
    local src = APP_SOURCE[id]
    if not src then cb({ error = 'unknown' }) return end
    if GetResourceState(src.res) ~= 'started' then cb({ error = 'off' }) return end
    V.Request(src.callback, function(res) cb(res or { error = 'x' }) end)
end)

-- ══════════════════════════════════════════════════════════════
-- Messages, contacts, preferences
-- ══════════════════════════════════════════════════════════════
local function relay(callback)
    return function(data, cb)
        V.Request(callback, function(res) cb(res or { error = 'x' }) end, data)
    end
end

RegisterNUICallback('conversation',  relay('v-phone:conversation'))
RegisterNUICallback('send',          relay('v-phone:send'))
RegisterNUICallback('contactSave',   relay('v-phone:contactSave'))
RegisterNUICallback('contactDelete', relay('v-phone:contactDelete'))
RegisterNUICallback('groupCreate',   relay('v-phone:groupCreate'))

--- Share where you are. The coordinates come from the PED, not from the page: a page
--- that could name a position could claim to be anywhere.
RegisterNUICallback('sendloc', function(data, cb)
    local c = GetEntityCoords(PlayerPedId())
    local payload = { kind = 'location', attachment = string.format('%.1f;%.1f', c.x, c.y) }
    if data and data.group then payload.group = data.group else payload.number = data and data.number end
    V.Request('v-phone:send', function(res) cb(res or { error = 'x' }) end, payload)
end)
RegisterNUICallback('prefs',         relay('v-phone:prefs'))
RegisterNUICallback('lookup',        relay('v-phone:lookup'))

RegisterNUICallback('close', function(_, cb) closePhone(); cb('ok') end)

-- Re-ask the server for everything it owns. The page calls this after any write instead of
-- patching its local copy, because a UI that edits its own snapshot is a UI that will
-- eventually disagree with the database.
RegisterNUICallback('refresh', function(_, cb)
    V.Request('v-phone:open', function(res)
        if res and res.ok then myNumber = res.number end
        cb(res or { error = 'x' })
    end)
end)

-- ══════════════════════════════════════════════════════════════
-- The apps that do more than read
-- ══════════════════════════════════════════════════════════════
-- Each of these forwards to the module that owns the action, so the module's own
-- validation, notifications and settings all still apply. None of them decide anything.

RegisterNUICallback('places', relay('v-phone:places'))
RegisterNUICallback('install', relay('v-phone:install'))

--- The card belongs to v-banking, which mints it and owns the number. The wallet app
--- only displays it, so this reads and never writes.
RegisterNUICallback('card', function(_, cb)
    if GetResourceState('v-banking') ~= 'started' then cb({ error = 'off' }) return end
    V.Request('v-banking:card', function(res) cb(res or { error = 'x' }) end)
end)

--- Setting a waypoint is the one thing a phone map is actually for. Purely local: it
--- moves a marker on this player's own minimap and touches nothing else.
RegisterNUICallback('waypoint', function(data, cb)
    local x, y = tonumber(data and data.x), tonumber(data and data.y)
    if not x or not y then cb({ error = 'x' }) return end
    SetNewWaypoint(x + 0.0, y + 0.0)
    cb({ ok = true })
end)

RegisterNUICallback('music', function(data, cb)
    if GetResourceState('v-music') ~= 'started' then cb({ error = 'off' }) return end
    V.Request('v-music:control', function(res) cb(res or { error = 'x' }) end, data)
end)

RegisterNUICallback('payRent', function(data, cb)
    if GetResourceState('v-housing') ~= 'started' then cb({ error = 'off' }) return end
    V.Request('v-housing:payRent', function(res) cb(res or { error = 'x' }) end, data)
end)

--- The MDT reads v-police directly. `isCop` is re-checked there on every call, so the
--- app gate in the registry only decides whether the icon is drawn.
RegisterNUICallback('mdt', function(data, cb)
    if GetResourceState('v-police') ~= 'started' then cb({ error = 'off' }) return end
    local op = tostring((data and data.op) or '')
    if op == 'lookup' then
        V.Request('v-police:lookup', function(res) cb(res or { error = 'x' }) end,
            { query = data.query })
    elseif op == 'warrants' then
        V.Request('v-police:warrants', function(res) cb(res or { error = 'x' }) end)
    else
        cb({ error = 'x' })
    end
end)

-- ══════════════════════════════════════════════════════════════
-- Camera, health and layout
-- ══════════════════════════════════════════════════════════════

--- v-status already tracks hunger, thirst, stress, bleeding and illness, so the Health
--- app reads them rather than keeping a second set that would drift.
RegisterNUICallback('health', function(_, cb)
    if GetResourceState('v-status') ~= 'started' then cb({ error = 'off' }) return end
    local st = exports['v-status']:Get() or {}
    cb({
        ok = true,
        hunger = st.hunger, thirst = st.thirst, stress = st.stress,
        bleed = st.bleed, sick = st.sick,
        armour = GetPedArmour(PlayerPedId()),
        health = GetEntityHealth(PlayerPedId()) - 100,   -- GTA floors a living ped at 100
    })
end)

RegisterNUICallback('photos', relay('v-phone:photo'))

--- The social apps. One relay with a whitelist, because the page names an operation and
--- the client decides which callbacks that can ever mean - the same shape as the SDK.
local SOCIAL_OPS = {
    me = true, setup = true, feed = true, post = true, like = true,
    hushMe = true, hushSetup = true, hushNext = true, hushChoice = true,
}

RegisterNUICallback('social', function(data, cb)
    if GetResourceState('v-social') ~= 'started' then cb({ error = 'off' }) return end
    local op = tostring((data and data.op) or '')
    if not SOCIAL_OPS[op] then cb({ error = 'forbidden' }) return end
    V.Request('v-social:' .. op, function(res) cb(res or { error = 'x' }) end, data)
end)

--- What the widgets show. Both are the GAME's: the weather the server is actually
--- running (v-admin replicates it on GlobalState) and the in-game clock. A widget
--- showing the player's real-world time would be showing the wrong clock.
RegisterNUICallback('ambient', function(_, cb)
    cb({
        ok = true,
        weather = tostring(GlobalState.vweather or GetPrevWeatherTypeHashName() or 'CLEAR'),
        hours = GetClockHours(), minutes = GetClockMinutes(),
        day = GetClockDayOfMonth(), month = GetClockMonth() + 1,
    })
end)

--- Take a picture.
---
--- screenshot-basic uploads it and hands back a URL; the phone stores the URL. There is
--- deliberately no path for a data URI: a photo kept as base64 in a metadata column is
--- megabytes per shot, and the operator's upload target is the whole reason the camera
--- setting has one.
RegisterNUICallback('shoot', function(_, cb)
    if GetResourceState('screenshot-basic') ~= 'started' then cb({ error = 'nocam' }) return end
    local target = tostring(V.Setting('cameraUpload', '') or '')
    if target == '' then cb({ error = 'noupload' }) return end

    -- Hide the phone for the shot, or every photo is a picture of the phone.
    SendNUIMessage({ action = 'shutter' })
    SetNuiFocus(false, false)
    Wait(120)

    exports['screenshot-basic']:requestScreenshotUpload(target, 'files[]', { encoding = 'jpg', quality = 0.85 },
        function(data)
            SetNuiFocus(true, true)
            local ok, res = pcall(json.decode, data)
            -- Upload targets disagree about where they put the URL, so look in the two
            -- shapes that cover almost all of them and fail honestly otherwise.
            local url = ok and res and (
                (res.attachments and res.attachments[1] and res.attachments[1].url)
                or res.url or res.link or (res.data and res.data.link))
            if not url then cb({ error = 'upload' }) return end
            V.Request('v-phone:photo', function(r) cb(r or { error = 'x' }) end,
                { op = 'add', url = url })
        end)
end)

-- ══════════════════════════════════════════════════════════════
-- App SDK relays
-- ══════════════════════════════════════════════════════════════
-- A third-party app talks to its OWN server code and nothing else. The full callback
-- and event names are composed here from the app id the phone supplies, so a page has
-- no way to spell `v-banking:withdraw` even if it tries: the id never comes from the
-- page's payload.
local function sdkApp(data)
    local app = tostring((data and data.app) or ''):gsub('[^%w_-]', '')
    if app == '' then return nil end
    return app
end

RegisterNUICallback('sdkRequest', function(data, cb)
    local app = sdkApp(data)
    local method = tostring((data and data.method) or ''):gsub('[^%w_-]', '')
    if not app or method == '' then cb({ error = 'forbidden' }) return end
    V.Request(app .. ':' .. method, function(res) cb(res == nil and { ok = true } or res) end, data.payload)
end)

RegisterNUICallback('sdkEmit', function(data, cb)
    local app = sdkApp(data)
    local event = tostring((data and data.event) or ''):gsub('[^%w_-]', '')
    if not app or event == '' then cb({ error = 'forbidden' }) return end
    TriggerServerEvent(app .. ':' .. event, data.payload)
    cb({ ok = true })
end)

RegisterNUICallback('sdkStorage', function(data, cb)
    local app = sdkApp(data)
    if not app then cb({ error = 'forbidden' }) return end
    V.Request('v-phone:storage', function(res) cb(res or { error = 'x' }) end, {
        app = app, op = data.op, key = data.key, value = data.value,
    })
end)

-- ══════════════════════════════════════════════════════════════
-- Calls
-- ══════════════════════════════════════════════════════════════
-- The audio is v-voice's; these four handlers only start and stop it at the right moments.
local function joinCallAudio()
    if voice() then exports['v-voice']:PhoneCallStart() end
end

local function leaveCallAudio()
    if voice() then exports['v-voice']:PhoneCallEnd() end
end

RegisterNUICallback('call', function(data, cb)
    V.Request('v-phone:call', function(res)
        if not res or res.error then
            V.Notify(L('ph.err_' .. ((res and res.error) or 'x')), 'error')
        end
        cb(res or { error = 'x' })
    end, data)
end)

RegisterNUICallback('answer', function(_, cb)
    V.Request('v-phone:answer', function(res) cb(res or { error = 'x' }) end)
end)

RegisterNUICallback('hangup', function(_, cb)
    V.Request('v-phone:hangup', function(res) cb(res or { error = 'x' }) end)
end)

RegisterNetEvent('v-phone:client:callOut', function(data)
    call = { id = data.id, state = 'out', number = data.number }
    SendNUIMessage({ action = 'call', call = call })
end)

RegisterNetEvent('v-phone:client:callIn', function(data)
    call = { id = data.id, state = 'in', number = data.number }
    -- An incoming call opens the phone if it is closed: a ringing phone the player cannot
    -- see is a missed call they never had the chance to take.
    SendNUIMessage({ action = 'call', call = call })
    if not isOpen then openPhone() end
end)

RegisterNetEvent('v-phone:client:callActive', function(data)
    call = { id = data.id, state = 'active', number = call and call.number or nil }
    joinCallAudio()
    SendNUIMessage({ action = 'call', call = call })
end)

RegisterNetEvent('v-phone:client:callEnd', function(reason)
    -- Leave the voice channel even if the UI never got the start: an end that does not
    -- release the channel leaves the player audible to strangers across the map.
    leaveCallAudio()
    call = nil
    SendNUIMessage({ action = 'call', call = nil })
    if reason and reason ~= 'hangup' then V.Notify(L('ph.call_' .. reason), 'info') end
end)

RegisterNetEvent('v-phone:client:power', function(p)
    local wasLow = power.battery
    power = p or power
    SendNUIMessage({ action = 'power', power = power })

    -- Warn once on the way past each threshold, not every tick past it.
    local low, crit = 20, 5
    if power.battery <= crit and wasLow > crit then
        V.Notify(L('ph.battery_critical'), 'error')
    elseif power.battery <= low and wasLow > low then
        V.Notify(L('ph.battery_low'), 'warning')
    end
    if power.battery <= 0 and wasLow > 0 then
        closePhone()
        V.Notify(L('ph.battery_dead'), 'error')
    end
end)

-- ══════════════════════════════════════════════════════════════
-- Notifications
-- ══════════════════════════════════════════════════════════════
RegisterNetEvent('v-phone:client:message', function(msg)
    if isOpen then
        SendNUIMessage({ action = 'message', message = msg })
    else
        V.Notify((L('ph.new_message')):format(msg.from or '?'), 'info')
    end
end)

RegisterNetEvent('v-phone:client:banner', function(b)
    if isOpen then SendNUIMessage({ action = 'banner', banner = b })
    else V.Notify((b.title or '') .. ' ' .. (b.body or ''), 'info') end
end)

-- ══════════════════════════════════════════════════════════════
-- Housekeeping
-- ══════════════════════════════════════════════════════════════
exports('IsOpen',    function() return isOpen end)
exports('GetNumber', function() return myNumber end)
exports('Open',      function() openPhone() end)
exports('Close',     function() closePhone() end)
exports('OnCall',    function() return call end)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then
        leaveCallAudio()
        SetNuiFocus(false, false)
    end
end)

-- ── Theme ──────────────────────────────────────────────────────
-- A NUI page can only be messaged by the resource that owns it, so v-ui cannot reach this
-- one directly: it publishes a version and each module forwards it into its own page.
local function pushTheme()
    if GetResourceState('v-ui') ~= 'started' then return end
    SendNUIMessage({ action = 'v-ui:theme', version = exports['v-ui']:Version() })
end

AddEventHandler('v-ui:client:themeChanged', function() pushTheme() end)
CreateThread(function() Wait(4000); pushTheme() end)
