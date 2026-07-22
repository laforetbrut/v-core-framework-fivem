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
        state.action  = 'open'
        state.strings = strings()
        state.call    = call
        SendNUIMessage(state)
    end)
end

local function closePhone()
    if not isOpen then return end
    isOpen = false
    SetNuiFocus(false, false)
    exports['v-core']:MenuClosed('v-phone')
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
    jobs   = { res = 'v-cityhall', callback = 'v-phone:jobs' },
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
