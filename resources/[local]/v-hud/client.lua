-- v-hud | client
-- Feeds the NUI with money (v-core) + vitals (native + v-status), and
-- persists per-player HUD customization via KVP.

local loaded = false
local settings = { elements = { minimap = true }, minimapVehicleOnly = false }

-- Our own SQUARE minimap (QBCore method): the radar mask is swapped for the
-- shipped `squaremap` texture — the map becomes a clean square and the GTA:O
-- health/armour bars are no longer drawn at all. The whole thing is then
-- repositionable: the player's frame top-left (fractions) becomes a delta on
-- the tested base layout. `w`/`h` = the on-screen footprint sent to the NUI.
-- All in TOP-LEFT screen fractions (same system as the NUI frame, so the map
-- and the frame move together). map = the native square inside the frame; the
-- frame's extra bottom height is the cover that hides the GTA:O health/armour
-- bars (the square texture reshapes the map but doesn't remove those bars).
local MM = {
    default = { x = 0.013, y = 0.74 },      -- top-left of the frame (fractions)
    w = 0.150, h = 0.205,                    -- frame footprint sent to the NUI
    map = { dx = 0.004, dy = 0.004, w = 0.142, h = 0.150 },  -- native square inside
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

-- ── Minimap: square (QBCore method), repositionable ──
local function minimapPos()
    local p = settings.positions and settings.positions.minimap
    if p and type(p.x) == 'number' then return p.x, p.y end   -- stored as fractions
    return MM.default.x, MM.default.y
end

-- Aspect-ratio correction so the square stays square on ultrawide.
local function aspectOffset()
    local rx, ry = GetActiveScreenResolution()
    local ar = (ry ~= 0) and (rx / ry) or (16 / 9)
    if ar > (1920 / 1080) then return ((1920 / 1080 - ar) / 3.6) - 0.008 end
    return 0.0
end

-- Swap the radar mask for the square texture (removes the round frame AND the
-- GTA:O health/armour bars entirely). Done once.
local squareReady = false
local function loadSquareMask()
    if squareReady then return true end
    RequestStreamedTextureDict('squaremap', false)
    local t = 0
    while not HasStreamedTextureDictLoaded('squaremap') and t < 120 do Wait(50); t = t + 1 end
    if not HasStreamedTextureDictLoaded('squaremap') then return false end
    pcall(function() SetMinimapClipType(0) end)
    AddReplaceTexture('platform:/textures/graphics', 'radarmasksm', 'squaremap', 'radarmasksm')
    AddReplaceTexture('platform:/textures/graphics', 'radarmask1g', 'squaremap', 'radarmasksm')
    squareReady = true
    return true
end

-- Square map, positioned TOP-LEFT to match the NUI frame exactly (so drag goes
-- the right way and the cover strip lines up with the map).
local function setMinimapPositions()
    local px, py = minimapPos()
    local off = aspectOffset()
    local m = MM.map
    pcall(function() SetMinimapClipType(0) end)
    SetMinimapComponentPosition('minimap',      'L', 'T', px + off + m.dx,        py + m.dy,        m.w,        m.h)
    SetMinimapComponentPosition('minimap_mask', 'L', 'T', px + off + m.dx,        py + m.dy,        m.w,        m.h)
    SetMinimapComponentPosition('minimap_blur', 'L', 'T', px + off + m.dx - 0.012, py + m.dy - 0.012, m.w + 0.024, m.h + 0.024)
    SetBlipAlpha(GetNorthRadarBlip(), 0)
end

local refreshPending = false
local function scheduleRefresh()
    if refreshPending then return end
    refreshPending = true
    SetTimeout(220, function()
        refreshPending = false
        SetBigmapActive(true, false)
        Wait(0)
        SetBigmapActive(false, false)
    end)
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

-- Set up the square mask once loaded, then keep the layout asserted.
CreateThread(function()
    while not loaded do Wait(200) end
    loadSquareMask()
    Wait(300)
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

-- Restore the vanilla radar mask when the resource stops (dev restarts).
AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    pcall(function()
        RemoveReplaceTexture('platform:/textures/graphics', 'radarmasksm')
        RemoveReplaceTexture('platform:/textures/graphics', 'radarmask1g')
        SetMinimapClipType(0)
    end)
end)
