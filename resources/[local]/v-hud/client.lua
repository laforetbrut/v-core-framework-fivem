-- v-hud | client
-- Feeds the NUI with money (v-core) + vitals (native + v-status), and
-- persists per-player HUD customization via KVP.

local loaded = false
local settings = { elements = { minimap = true }, minimapVehicleOnly = false }

-- Our own minimap = the native radar, reframed & repositionable. Footprint and
-- fine calibration in SCREEN FRACTIONS (nudge if the frame and the map don't
-- line up perfectly on your resolution — same values feed the NUI frame).
-- The frame's bottom strip (h - map.h - map.dy) covers the GTA:O health/armour
-- bars, which have no hide native and render at the bottom of the radar.
local MM = {
    default = { x = 0.0125, y = 0.723 },   -- top-left of the frame (fractions)
    w = 0.150, h = 0.225,                   -- frame size sent to the NUI
    map = { dx = 0.006, dy = 0.008, w = 0.138, h = 0.171 },  -- native map inside the frame
}

local function TL(k)
    local lang = (LocalPlayer.state and LocalPlayer.state.lang) or 'fr'
    return (Locales[lang] or Locales.fr or {})[k] or k
end

local function loadSettings()
    local raw = GetResourceKvpString('vhud:settings')
    if raw then
        local ok, parsed = pcall(json.decode, raw)
        if ok and parsed then settings = parsed end
    end
end

local function status()
    local ok, s = pcall(function() return exports['v-status']:Get() end)
    return (ok and s) or {}
end

local function sendStrings()
    local lang = (LocalPlayer.state and LocalPlayer.state.lang) or 'fr'
    SendNUIMessage({ action = 'strings', strings = Locales[lang] or Locales.fr or {} })
end

-- Push settings + strings to the NUI as soon as it's ready.
CreateThread(function()
    loadSettings()
    Wait(250)
    SendNUIMessage({ action = 'minimapFrame', w = MM.w, h = MM.h, default = MM.default })
    SendNUIMessage({ action = 'init', settings = settings or {} })
    sendStrings()
end)

-- ── Money ──
AddEventHandler('v-core:client:onPlayerLoaded', function(data)
    loaded = true
    sendStrings()   -- language is known now
    SendNUIMessage({ action = 'money', cash = data.money.cash, bank = data.money.bank })
end)

AddEventHandler('v-core:client:onMoneyChange', function(money)
    SendNUIMessage({ action = 'money', cash = money.cash, bank = money.bank, flash = true })
end)

-- ── Vitals poll ──
-- One-shot alerts when a need drops to/below 25% (re-armed above 32%).
local alerted = { hunger = false, thirst = false }
local ALERT_AT, ALERT_CLEAR = 25, 32

local function needAlert(key, val, titleKey, msgKey)
    if val <= ALERT_AT and not alerted[key] then
        alerted[key] = true
        pcall(function()
            exports['v-notify']:show({ type = 'warning', title = TL(titleKey), message = TL(msgKey), duration = 6500 })
        end)
    elseif val >= ALERT_CLEAR and alerted[key] then
        alerted[key] = false
    end
end

CreateThread(function()
    while true do
        Wait(350)
        if loaded then
            local ped = PlayerPedId()
            local pid = PlayerId()
            local s = status()
            local underwater = IsPedSwimmingUnderWater(ped)
            local hunger = s.hunger or 100
            local thirst = s.thirst or 100
            needAlert('hunger', hunger, 'alert.hungry_t', 'alert.hungry_m')
            needAlert('thirst', thirst, 'alert.thirsty_t', 'alert.thirsty_m')
            SendNUIMessage({ action = 'vitals', data = {
                health  = math.max(0, math.min(100, GetEntityHealth(ped) - 100)),
                armor   = GetPedArmour(ped),
                hunger  = hunger,
                thirst  = thirst,
                stress  = s.stress or 0,
                stamina = math.max(0, math.min(100, 100 - GetPlayerSprintStaminaRemaining(pid))),
                oxygen  = underwater and math.floor(GetPlayerUnderwaterTimeRemaining(pid) * 12) or 100,
                underwater = underwater,
            } })
        end
    end
end)

-- ── Hide the default GTA HUD pieces we replace ──
CreateThread(function()
    while true do
        Wait(0)
        HideHudComponentThisFrame(3)   -- cash (single-player)
        HideHudComponentThisFrame(4)   -- MP cash (we show our own money)
        HideHudComponentThisFrame(13)  -- cash change
    end
end)

-- ── Compass heading (only while the compass is enabled) ──
CreateThread(function()
    while true do
        if loaded and settings.elements and settings.elements.compass then
            SendNUIMessage({ action = 'heading', h = GetEntityHeading(PlayerPedId()) })
            Wait(80)
        else
            Wait(500)
        end
    end
end)

-- ── Minimap: our own reframed, repositionable radar ──
local function minimapPos()
    local p = settings.positions and settings.positions.minimap
    if p and type(p.x) == 'number' then return p.x, p.y end   -- stored as fractions
    return MM.default.x, MM.default.y
end

-- SetMinimapComponentPosition only takes effect after a bigmap refresh — debounce
-- one so drags/edits don't flicker the map.
local refreshPending = false
local function scheduleRefresh()
    if refreshPending then return end
    refreshPending = true
    SetTimeout(220, function()
        refreshPending = false
        SetRadarBigmapEnabled(true, false)
        Wait(0)
        SetRadarBigmapEnabled(false, false)
    end)
end

local function setMinimapPositions()
    local x, y = minimapPos()
    local m = MM.map
    SetMinimapComponentPosition('minimap',      'L', 'T', x + m.dx,         y + m.dy,         m.w,        m.h)
    SetMinimapComponentPosition('minimap_mask', 'L', 'T', x + m.dx,         y + m.dy,         m.w,        m.h)
    SetMinimapComponentPosition('minimap_blur', 'L', 'T', x + m.dx - 0.015, y + m.dy - 0.02,  m.w + 0.03, m.h + 0.04)
end

local function applyMinimap(refresh)
    local wantMap = not (settings.elements and settings.elements.minimap == false)
    if wantMap and settings.minimapVehicleOnly then
        wantMap = IsPedInAnyVehicle(PlayerPedId(), false)
    end
    DisplayRadar(wantMap)
    if not wantMap then return end
    setMinimapPositions()
    if refresh then scheduleRefresh() end
end

-- Force the custom layout to actually apply once the HUD is loaded.
CreateThread(function()
    while not loaded do Wait(200) end
    Wait(400)
    applyMinimap(true)
    while true do
        Wait(1500)
        applyMinimap(false)   -- re-assert position/visibility (no flicker)
    end
end)

-- Live update while the player drags the minimap frame in layout mode.
RegisterNUICallback('minimapMove', function(data, cb)
    if type(data.x) == 'number' then
        settings.positions = settings.positions or {}
        settings.positions.minimap = { x = data.x + 0.0, y = data.y + 0.0 }
        applyMinimap(true)
    end
    cb('ok')
end)

-- ── Settings (keybind, no chat command for players) ──
RegisterCommand('vhud_settings', function()
    if not loaded then return end
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'openSettings' })
end, false)
RegisterKeyMapping('vhud_settings', 'Open HUD settings', 'keyboard', 'F7')

RegisterNUICallback('saveSettings', function(data, cb)
    settings = data
    SetResourceKvpString('vhud:settings', json.encode(data))
    SetNuiFocus(false, false)
    applyMinimap(true)
    cb('ok')
end)

RegisterNUICallback('closeSettings', function(_, cb)
    SetNuiFocus(false, false)
    cb('ok')
end)

-- Restore on mid-session restart.
CreateThread(function()
    Wait(800)
    local core = exports['v-core']:GetCore()
    if core and core.isLoaded then
        loaded = true
        local pd = exports['v-core']:GetPlayerData()
        if pd and pd.money then
            SendNUIMessage({ action = 'money', cash = pd.money.cash, bank = pd.money.bank })
        end
    end
end)
