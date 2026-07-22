-- v-voice | client
-- Applies what the server decided. FiveM's Mumble backend does the audio; this file sets
-- the distances, joins the right channel to transmit, and reports state to the HUD.

local step      = Config.DefaultStep
local ranges    = { whisper = 3.0, normal = 8.0, shout = 20.0 }
local phoneCh   = Config.PhoneChannel
local listening = {}         -- [channelId] = true, every channel we monitor
local channel   = nil        -- the one we transmit on
local onRadio   = false      -- currently keyed
local muted     = false
local injured   = false

local function strings()
    return Locales[(LocalPlayer.state and LocalPlayer.state.lang) or 'fr'] or Locales.fr or {}
end
local function L(k) return strings()[k] or k end

local function stepKey() return Config.Proximity[step] and Config.Proximity[step].key or 'normal' end
local function stepLabel() return L('voice.' .. stepKey()) end

-- ── Proximity ──────────────────────────────────────────────────
--- Both distances matter: input is how far your voice carries, output is how far you hear.
--- Setting only one produces the classic "I can hear them but they cannot hear me".
local function applyRange()
    local r = ranges[stepKey()] or 8.0
    MumbleSetAudioInputDistance(r + 0.0)
    MumbleSetAudioOutputDistance((ranges.shout or 20.0) + 0.0)
end

local function refreshRanges()
    V.Request('v-voice:ranges', function(res)
        if type(res) ~= 'table' then return end
        ranges  = res.ranges or ranges
        injured = res.injured == true
        phoneCh = math.floor(tonumber(res.phone) or Config.PhoneChannel)
        applyRange()
    end)
end

local function cycle()
    step = step + 1
    if step > #Config.Proximity then step = 1 end
    applyRange()
    V.Notify((L('voice.now')):format(stepLabel()), 'info')
end

RegisterCommand('vvoice_cycle', cycle, false)
RegisterKeyMapping('vvoice_cycle', 'Voice: cycle proximity', 'keyboard', Config.Keys.cycle or 'Z')

-- ── Radio ──────────────────────────────────────────────────────
--- The server sends the whole set every time, so this only has to reconcile: add what is
--- new, drop what is gone. Sending deltas would mean the client and the server could
--- disagree about what is being monitored, and only one of them is right.
RegisterNetEvent('v-voice:client:channels', function(list, transmit)
    local want = {}
    for _, id in ipairs(list or {}) do want[math.floor(id)] = true end

    for id in pairs(listening) do
        if not want[id] then MumbleRemoveVoiceChannelListen(id); listening[id] = nil end
    end
    for id in pairs(want) do
        if not listening[id] then MumbleAddVoiceChannelListen(id); listening[id] = true end
    end

    channel = transmit and math.floor(transmit) or nil
    TriggerEvent('v-voice:client:onChannels', list or {}, channel)
end)

RegisterNetEvent('v-voice:client:muted', function(on)
    muted = on and true or false
    if muted and onRadio then
        onRadio = false
        MumbleClearVoiceChannel()
    end
end)

local function startTalking()
    if onRadio or muted or not channel then return end
    -- Asked every keypress rather than cached: it is the only place that can know the
    -- player is still allowed on this channel, still has the radio and is not cuffed.
    V.Request('v-voice:mayTransmit', function(ok)
        if ok ~= true then return end
        onRadio = true
        MumbleSetVoiceChannel(channel)
        -- Wide input while transmitting, so the radio is not also proximity-limited.
        MumbleSetAudioInputDistance(0.0)
        local ped = PlayerPedId()
        if not IsPedInAnyVehicle(ped, false) then
            RequestAnimDict('random@arrests')
            local t = 0
            while not HasAnimDictLoaded('random@arrests') and t < 60 do Wait(10); t = t + 1 end
            if HasAnimDictLoaded('random@arrests') then
                TaskPlayAnim(ped, 'random@arrests', 'generic_radio_chatter', 8.0, -8.0, -1, 49, 0, false, false, false)
            end
        end
    end)
end

local function stopTalking()
    if not onRadio then return end
    onRadio = false
    MumbleClearVoiceChannel()
    applyRange()
    StopAnimTask(PlayerPedId(), 'random@arrests', 'generic_radio_chatter', 1.0)
end

RegisterCommand('+vvoice_radio', startTalking, false)
RegisterCommand('-vvoice_radio', stopTalking, false)
RegisterKeyMapping('+vvoice_radio', 'Voice: talk on the radio', 'keyboard', Config.Keys.radio or 'CAPITAL')

-- ── Phone submix ───────────────────────────────────────────────
-- Exposed for v-phone: a call joins its own channel so it carries across the map and is
-- inaudible to somebody standing next to you.
exports('PhoneCallStart', function()
    MumbleAddVoiceChannelListen(phoneCh)
    MumbleSetVoiceChannel(phoneCh)
end)

exports('PhoneCallEnd', function()
    MumbleClearVoiceChannel()
    MumbleRemoveVoiceChannelListen(phoneCh)
    applyRange()
end)

-- ── State for the HUD ──────────────────────────────────────────
exports('GetState', function()
    return {
        step    = stepKey(),
        label   = stepLabel(),
        range   = ranges[stepKey()] or 8.0,
        channel = channel,
        radio   = onRadio,
        talking = NetworkIsPlayerTalking(PlayerId()),
        muted   = muted,
        injured = injured,
    }
end)

exports('GetChannel',   function() return channel end)
exports('GetListening', function()
    local out = {}
    for id in pairs(listening) do out[#out + 1] = id end
    table.sort(out)
    return out
end)
exports('GetStepLabel', function() return stepLabel() end)

-- ── Boot ───────────────────────────────────────────────────────
V.Ready(function()
    Wait(1500)
    -- The Mumble backend needs a moment before it will accept distances.
    local t = 0
    while not MumbleIsConnected() and t < 100 do Wait(200); t = t + 1 end
    refreshRanges()
end)

-- Ranges are admin-tunable and depend on how hurt the player is, so they are re-read
-- rather than cached for the session.
CreateThread(function()
    while true do
        Wait(20000)
        refreshRanges()
    end
end)

V.OnSetting(function() refreshRanges() end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for id in pairs(listening) do MumbleRemoveVoiceChannelListen(id) end
    MumbleClearVoiceChannel()
end)
