-- v-voice | server
-- Channel membership and range are the two things a voice module must never take from the
-- client. A client that picks its own channel can listen to the police; a client that sets
-- its own range has a megaphone. Both are decided here and mirrored down.

local Core
local Channels = {}      -- [id] = row
-- A handheld listens to several channels and talks on one. Keeping them separate is the
-- whole difference between a radio and a walkie-talkie.
local Listen   = {}      -- [source] = { [channelId] = true }
local Transmit = {}      -- [source] = channelId or nil
local Muted = {}         -- [citizenid] = true

local function num(v, d) return tonumber(v) or d or 0 end

local function L(src, k)
    local p = Core and Core.GetPlayer(src)
    local lang = (p and p.lang) or 'fr'
    return (Locales[lang] or Locales.fr or {})[k] or k
end

-- ── Settings ──────────────────────────────────────────────────
V.Module({
    label = 'Voice', category = 'gameplay',
    settings = {
        { key = 'whisper',    label = 'Whisper range (m)',      type = 'number', default = Config.Proximity[1].range, min = 0.5, max = 50, step = 0.5 },
        { key = 'normal',     label = 'Normal range (m)',       type = 'number', default = Config.Proximity[2].range, min = 0.5, max = 80, step = 0.5 },
        { key = 'shout',      label = 'Shout range (m)',        type = 'number', default = Config.Proximity[3].range, min = 0.5, max = 150, step = 0.5 },
        { key = 'radio',      label = 'Radio enabled',          type = 'bool',   default = true },
        { key = 'radioItem',  label = 'Radio item required (blank = none)', type = 'string', default = Config.RadioItem, maxLength = 40 },
        { key = 'radioWhileCuffed', label = 'Cuffed players can use the radio', type = 'bool', default = false },
        { key = 'maxChannels', label = 'Channels one radio can monitor', type = 'number', default = 4, min = 1, max = 12, step = 1,
          hint = 'Without a ceiling, listening to everything beats choosing and the radio stops being a decision.' },
        { key = 'injuredMult', label = 'Range multiplier when badly hurt', type = 'number', default = Config.Injured.rangeMult, min = 0.1, max = 1, step = 0.05 },
        { key = 'bleedThreshold', label = 'Bleed level that counts as badly hurt', type = 'number', default = Config.Injured.bleedThreshold, min = 1, max = 5, step = 1 },
        { key = 'phoneChannel', label = 'Mumble channel used for calls', type = 'number', default = Config.PhoneChannel, min = 1, max = 65000, step = 1 },
    },
})

-- Consumers ask for the capability, not the resource: a server that replaces this
-- module keeps every consumer working.
V.Provide('voice')


-- ── Channels ──────────────────────────────────────────────────
local function loadChannels()
    Channels = {}
    if GetResourceState('v-world') ~= 'started' then return end
    for _, c in ipairs(exports['v-world']:GetRadio() or {}) do
        if c.enabled ~= false then Channels[math.floor(num(c.id))] = c end
    end
end

--- May this player use this channel? The gate reuses the job and gang concepts the rest of
--- the framework already gates on, rather than inventing a third permission list.
local function mayUse(src, id)
    local c = Channels[math.floor(num(id))]
    if not c then return false, 'nochannel' end

    local p = Core.GetPlayer(src)
    if not p then return false, 'x' end

    local grade = math.floor(num(c.min_grade))
    if c.job then
        -- `player.job` is a TABLE, never a string.
        if type(p.job) ~= 'table' or p.job.name ~= c.job then return false, 'notyours' end
        if math.floor(num(p.job.grade)) < grade then return false, 'grade' end
    elseif c.gang then
        if type(p.gang) ~= 'table' or p.gang.name ~= c.gang then return false, 'notyours' end
        if math.floor(num(p.gang.grade)) < grade then return false, 'grade' end
    end
    return true
end

--- Every channel this player is allowed on, so the radio UI lists what they can reach
--- instead of offering channels that will refuse them.
local function availableTo(src)
    local out = {}
    for id, c in pairs(Channels) do
        if mayUse(src, id) then
            out[#out + 1] = { id = id, label = c.label, job = c.job, gang = c.gang }
        end
    end
    table.sort(out, function(a, b) return a.id < b.id end)
    return out
end

local function hasRadio(src)
    local item = tostring(V.Setting('radioItem', Config.RadioItem) or '')
    if item == '' then return true end
    return (tonumber(V.Use('v-inventory').GetItemCount(src, item)) or 0) >= 1
end

-- ── Join / leave ──────────────────────────────────────────────
local function pushState(src)
    local list = {}
    for id in pairs(Listen[src] or {}) do list[#list + 1] = id end
    table.sort(list)
    TriggerClientEvent('v-voice:client:channels', src, list, Transmit[src])
end

--- Leave one channel, or every channel when `id` is nil.
local function leave(src, id, quiet)
    if id then
        if not (Listen[src] and Listen[src][id]) then return end
        Listen[src][id] = nil
        if Transmit[src] == id then Transmit[src] = next(Listen[src]) end
    else
        Listen[src], Transmit[src] = nil, nil
    end
    pushState(src)
    if not quiet then Core.Notify(src, L(src, 'voice.left'), 'info') end
end

V.Callback('v-voice:channels', function(src, resolve)
    local list = {}
    for id in pairs(Listen[src] or {}) do list[#list + 1] = id end
    table.sort(list)
    resolve({ ok = true, channels = availableTo(src), listening = list,
              transmit = Transmit[src],
              radio = V.SettingBool('radio', true) and hasRadio(src) })
end)

V.Callback('v-voice:join', function(src, resolve, data)
    if not V.SettingBool('radio', true) then resolve({ error = 'off' }) return end
    if not hasRadio(src) then resolve({ error = 'noradio' }) return end

    local id = math.floor(num(data and data.channel))
    if id <= 0 then leave(src, nil); resolve({ ok = true, channel = nil }) return end

    local ok, why = mayUse(src, id)
    if not ok then resolve({ error = why or 'notyours' }) return end

    -- A ceiling on how many channels one radio monitors: without it, "listen to
    -- everything" is a strictly better choice than picking, and the device stops being a
    -- decision.
    Listen[src] = Listen[src] or {}
    local n = 0
    for _ in pairs(Listen[src]) do n = n + 1 end
    local maxCh = math.floor(num(V.Setting('maxChannels', 4), 4))
    if not Listen[src][id] and n >= maxCh then resolve({ error = 'full', max = maxCh }) return end

    Listen[src][id] = true
    -- The first channel joined becomes the transmit target, so a player who only ever
    -- joins one never has to think about the distinction.
    if not Transmit[src] then Transmit[src] = id end
    pushState(src)
    resolve({ ok = true, channel = id, label = Channels[id] and Channels[id].label or tostring(id) })
end)

V.Callback('v-voice:leave', function(src, resolve, data)
    local id = data and math.floor(num(data.channel))
    leave(src, (id and id > 0) and id or nil)
    resolve({ ok = true })
end)

--- Which of the channels you already monitor do you talk on? Re-gated, because a rank can
--- change between joining and keying up.
V.Callback('v-voice:setTransmit', function(src, resolve, data)
    local id = math.floor(num(data and data.channel))
    if id <= 0 then Transmit[src] = nil; pushState(src); resolve({ ok = true }) return end
    if not (Listen[src] and Listen[src][id]) then resolve({ error = 'notlistening' }) return end
    if not mayUse(src, id) then resolve({ error = 'notyours' }) return end
    Transmit[src] = id
    pushState(src)
    resolve({ ok = true, channel = id })
end)

--- Asked every time the client wants to key the mic. Cheap, and it is the only place that
--- can know the player is still allowed on the channel a second after they joined.
V.Callback('v-voice:mayTransmit', function(src, resolve)
    local id = Transmit[src]
    if not id then resolve(false) return end
    local p = Core.GetPlayer(src)
    if p and Muted[p.citizenid] then resolve(false) return end
    if not hasRadio(src) then leave(src, nil, true); resolve(false) return end
    if not V.SettingBool('radioWhileCuffed', false) then
        if V.Use('v-police').IsCuffed(src) == true then resolve(false) return end
    end
    if not mayUse(src, id) then leave(src, id, true); resolve(false) return end
    resolve(true)
end)

--- The ranges and the injury penalty, resolved server-side. A client that sets its own
--- range is a megaphone, so the client only ever asks which step it is on.
V.Callback('v-voice:ranges', function(src, resolve)
    local ranges = {
        whisper = num(V.Setting('whisper', Config.Proximity[1].range), Config.Proximity[1].range),
        normal  = num(V.Setting('normal',  Config.Proximity[2].range), Config.Proximity[2].range),
        shout   = num(V.Setting('shout',   Config.Proximity[3].range), Config.Proximity[3].range),
    }
    local mult = 1.0
    if GetResourceState('v-status') == 'started' then
        local st = V.Use('v-status').Get(src)
        local threshold = num(V.Setting('bleedThreshold', Config.Injured.bleedThreshold), Config.Injured.bleedThreshold)
        if type(st) == 'table' and num(st.bleed) >= threshold then
            mult = num(V.Setting('injuredMult', Config.Injured.rangeMult), Config.Injured.rangeMult)
        end
    end
    for k, v in pairs(ranges) do ranges[k] = math.max(0.5, v * mult) end
    resolve({ ranges = ranges, injured = mult < 1.0,
              phone = math.floor(num(V.Setting('phoneChannel', Config.PhoneChannel), Config.PhoneChannel)) })
end)

-- ── Staff mute ────────────────────────────────────────────────
-- A mute a staff member can apply without touching the voice server. It survives a relog
-- because it is keyed on the citizen id, not the session.
local function setMute(cid, on)
    Muted[cid] = on or nil
    local p = Core.GetPlayerByCitizenId(cid)
    if p then
        TriggerClientEvent('v-voice:client:muted', p.source, on and true or false)
        if on then leave(p.source, true) end
    end
end

exports('Mute',     function(cid) setMute(tostring(cid or ''), true) end)
exports('Unmute',   function(cid) setMute(tostring(cid or ''), false) end)
exports('IsMuted',  function(cid) return Muted[tostring(cid or '')] == true end)
exports('GetChannel',   function(src) return Transmit[src] end)
exports('GetListening', function(src)
    local out = {}
    for id in pairs(Listen[src] or {}) do out[#out + 1] = id end
    table.sort(out)
    return out
end)
exports('GetChannels', function() return Channels end)

--- Force somebody onto a channel from another script (a faction radio handed out by the
--- boss menu, a scripted dispatch). Still gated: the gate is the point.
exports('JoinChannel', function(src, id)
    local ok = mayUse(src, id)
    if not ok then return false end
    id = math.floor(num(id))
    Listen[src] = Listen[src] or {}
    Listen[src][id] = true
    if not Transmit[src] then Transmit[src] = id end
    pushState(src)
    return true
end)

-- ── Boot ──────────────────────────────────────────────────────
AddEventHandler('v-world:server:changed', function(domain)
    if domain == nil or domain == 'radio' then
        loadChannels()
        -- Somebody sitting on a channel an admin has just deleted or re-gated has to be
        -- taken off it, or the edit does nothing until they relog.
        for src, set in pairs(Listen) do
            for id in pairs(set) do
                if not mayUse(src, id) then leave(src, id, true) end
            end
        end
    end
end)

AddEventHandler('playerDropped', function()
    Listen[source], Transmit[source] = nil, nil
end)

-- Leaving a job or a gang leaves its channel, with no extra bookkeeping.
AddEventHandler('v-core:server:onJobChange', function(src)
    for id in pairs(Listen[src] or {}) do
        if not mayUse(src, id) then leave(src, id, true) end
    end
end)

V.Ready(function(core)
    Core = core
    local tries = 0
    while GetResourceState('v-world') == 'started' and not exports['v-world']:IsReady() and tries < 100 do
        Wait(100); tries = tries + 1
    end
    if GetResourceState('v-world') == 'started' then
        exports['v-world']:SeedRadio(Config.Channels)
        loadChannels()
    end
end)
