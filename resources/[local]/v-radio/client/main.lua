-- v-radio | client
-- The handheld. `v-voice` is the transport and keeps every permission decision; this is
-- the object in your hand.
--
-- **This module never decides who may use a channel.** It asks v-voice, which asks
-- v-factions and v-police. A device that decides its own channel list is a device that can
-- be edited.

local open = false
local state = { channels = {}, listening = {}, transmit = nil, radio = false }
local presets = {}          -- [slot] = channelId, saved per player in KVP

local function strings()
    return Locales[(LocalPlayer.state and LocalPlayer.state.lang) or 'fr'] or Locales.fr or {}
end
local function L(k) return strings()[k] or k end

-- ── Presets ────────────────────────────────────────────────────
-- KVP rather than the database: a preset is a personal convenience, not world state, and
-- it should not cost a round trip to read.
local function loadPresets()
    local raw = GetResourceKvpString('vradio:presets')
    if not raw then return end
    local ok, parsed = pcall(json.decode, raw)
    if ok and type(parsed) == 'table' then presets = parsed end
end

local function savePresets()
    SetResourceKvpString('vradio:presets', json.encode(presets))
end

-- ── State ──────────────────────────────────────────────────────
local function refresh(cb)
    V.Request('v-voice:channels', function(res)
        if not res or res.error then if cb then cb(false) end return end
        state.channels  = res.channels or {}
        state.listening = res.listening or {}
        state.transmit  = res.transmit
        state.radio     = res.radio == true
        state.presetSlots = math.floor(tonumber(V.Setting('presetSlots', Config.PresetSlots)) or 6)
        state.showGate    = V.SettingBool('showGate', true)
        if open then
            SendNUIMessage({ action = 'data', data = state, presets = presets, strings = strings() })
        end
        if cb then cb(true) end
    end)
end

-- v-voice pushes the whole set whenever it changes, including when an admin re-gates a
-- channel out from under somebody. Following that event means the device never shows a
-- channel the player was just removed from.
AddEventHandler('v-voice:client:onChannels', function(list, transmit)
    state.listening = list or {}
    state.transmit = transmit
    if open then
        SendNUIMessage({ action = 'data', data = state, presets = presets, strings = strings() })
    end
end)

-- ── Panel ──────────────────────────────────────────────────────
local function close()
    if not open then return end
    open = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
    if GetResourceState('v-core') == 'started' then
        pcall(function() exports['v-core']:MenuClosed('v-radio') end)
    end
end

local function openPanel()
    if open then close() return end
    refresh(function(ok)
        if not ok then return end
        if not state.radio then
            V.Notify(L('radio.err_noradio'), 'error')
            return
        end
        open = true
        SetNuiFocus(true, true)
        if GetResourceState('v-core') == 'started' then
            pcall(function() exports['v-core']:MenuOpened('v-radio') end)
        end
        SendNUIMessage({ action = 'open', data = state, presets = presets, strings = strings() })
    end)
end

RegisterCommand('vradio', openPanel, false)
RegisterKeyMapping('vradio', 'Open the radio', 'keyboard', Config.Key or 'F3')

-- ── Actions ────────────────────────────────────────────────────
local function relay(name, payload, after)
    V.Request(name, function(res)
        if res and res.ok then
            if after then after(res) end
            refresh()
        else
            local key = (res and res.error) or 'x'
            local msg = L('radio.err_' .. key)
            if key == 'full' and res and res.max then msg = (msg):format(res.max) end
            V.Notify(msg, 'error')
        end
    end, payload)
end

RegisterNUICallback('close', function(_, cb) close(); cb('ok') end)

RegisterNUICallback('toggle', function(d, cb)
    cb('ok')
    local id = math.floor(tonumber(d and d.channel) or 0)
    if id <= 0 then return end
    local listening = false
    for _, c in ipairs(state.listening) do if c == id then listening = true break end end
    if listening then
        relay('v-voice:leave', { channel = id })
    else
        relay('v-voice:join', { channel = id }, function()
            if V.SettingBool('clickOnJoin', true) then
                PlaySoundFrontend(-1, 'CLICK_BACK', 'HUD_MINI_GAME_SOUNDSET', true)
            end
        end)
    end
end)

RegisterNUICallback('transmit', function(d, cb)
    cb('ok')
    relay('v-voice:setTransmit', { channel = math.floor(tonumber(d and d.channel) or 0) })
end)

RegisterNUICallback('leaveAll', function(_, cb)
    cb('ok')
    relay('v-voice:leave', {})
end)

--- A preset is a shortcut, not a permission: saving one that later stops being allowed
--- simply fails to join, with v-voice giving the reason.
RegisterNUICallback('savePreset', function(d, cb)
    cb('ok')
    local slot = tostring(math.floor(tonumber(d and d.slot) or 0))
    local id = math.floor(tonumber(d and d.channel) or 0)
    if slot == '0' then return end
    if id <= 0 then presets[slot] = nil else presets[slot] = id end
    savePresets()
    if open then SendNUIMessage({ action = 'data', data = state, presets = presets, strings = strings() }) end
end)

RegisterNUICallback('usePreset', function(d, cb)
    cb('ok')
    local id = presets[tostring(math.floor(tonumber(d and d.slot) or 0))]
    if not id then return end
    relay('v-voice:join', { channel = id })
end)

-- ── Boot ───────────────────────────────────────────────────────
V.Ready(function()
    loadPresets()
    Wait(2500)
    refresh()
end)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() and open then SetNuiFocus(false, false) end
end)

local function pushTheme()
    if GetResourceState('v-ui') ~= 'started' then return end
    pcall(function() exports['v-ui']:Push() end)
end
AddEventHandler('v-ui:client:themeChanged', function() pushTheme() end)
CreateThread(function() Wait(4000); pushTheme() end)

exports('GetPresets', function() return presets end)
exports('IsOpen',     function() return open end)
