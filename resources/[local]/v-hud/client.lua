-- v-hud | client
-- Feeds the NUI with money (v-core) + vitals (native + v-status), and
-- persists per-player HUD customization via KVP.

local loaded = false
local settings = { elements = { minimap = true }, minimapVehicleOnly = false }

-- ── Square minimap (draggable + resizable) ──────────────────────────────
-- The NATIVE map is the single source of truth: it is positioned in COMPONENT
-- space (posX/posY/scale, qb-hud square layout — blip centred). The NUI frame
-- is then SLAVED to the map's TRUE on-screen rect, which we read back with the
-- engine's own gfx round-trip (SetScriptGfxAlign + GetScriptGfxPosition) — that
-- already applies GetSafeZoneSize() and the aspect transform, so the overlay is
-- pixel-perfect on any resolution/safezone. Drag = pixel delta -> 1:1 component
-- delta; resize = a single scale factor. (Method verified against the CFX
-- cookbook + Dalrae1/MinimapPositionFiveM + qb-hud.)
local map = { posX = 0.0, posY = 0.0, scale = 1.0 }   -- component-space offset + size
local hudHidden = false

local function TL(k)
    local lang = (LocalPlayer.state and LocalPlayer.state.lang) or 'fr'
    return (Locales[lang] or Locales.fr or {})[k] or k
end

local function loadSettings()
    local raw = GetResourceKvpString('vhud:settings')
    if raw then
        local ok, parsed = pcall(json.decode, raw)
        if ok and type(parsed) == 'table' then settings = parsed end
    end
    local m = settings.map
    if type(m) == 'table' then
        map.posX  = tonumber(m.posX) or 0.0
        map.posY  = tonumber(m.posY) or 0.0
        map.scale = math.min(2.0, math.max(0.5, tonumber(m.scale) or 1.0))
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

local lastVitals = nil
local function vitalsEqual(a, b)
    if not b then return false end
    for k, v in pairs(a) do if b[k] ~= v then return false end end
    return true
end

CreateThread(function()
    while true do
        Wait(250)
        if loaded then
            local ped = PlayerPedId()
            local pid = PlayerId()
            local s = status()
            local underwater = IsPedSwimmingUnderWater(ped)
            local hunger = s.hunger or 100
            local thirst = s.thirst or 100
            needAlert('hunger', hunger, 'alert.hungry_t', 'alert.hungry_m')
            needAlert('thirst', thirst, 'alert.thirsty_t', 'alert.thirsty_m')
            local data = {
                health  = math.max(0, math.min(100, GetEntityHealth(ped) - 100)),
                armor   = GetPedArmour(ped),
                hunger  = hunger,
                thirst  = thirst,
                stress  = s.stress or 0,
                stamina = math.max(0, math.min(100, 100 - GetPlayerSprintStaminaRemaining(pid))),
                oxygen  = underwater and math.floor(GetPlayerUnderwaterTimeRemaining(pid) * 12) or 100,
                underwater = underwater,
            }
            -- only push to the NUI when something actually changed (smoother, no churn)
            if not vitalsEqual(data, lastVitals) then
                lastVitals = data
                SendNUIMessage({ action = 'vitals', data = data })
            end
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

-- ── Minimap: native map = source of truth, NUI frame slaved to its rect ──
local function minimapEnabled()
    if settings.elements and settings.elements.minimap == false then return false end
    if settings.minimapVehicleOnly then return IsPedInAnyVehicle(PlayerPedId(), false) end
    return true
end

-- Swap the radar mask for the square texture (clean square shape). Done once.
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

-- Lightweight re-try, called from the minimap loop: if the streamed dict missed
-- its first load window (fast resource restart), keep nudging until it lands so
-- the square mask always recovers instead of staying round for the session.
local function retrySquareMask()
    if squareReady then return end
    RequestStreamedTextureDict('squaremap', false)
    if not HasStreamedTextureDictLoaded('squaremap') then return end
    pcall(function() SetMinimapClipType(0) end)
    AddReplaceTexture('platform:/textures/graphics', 'radarmasksm', 'squaremap', 'radarmasksm')
    AddReplaceTexture('platform:/textures/graphics', 'radarmask1g', 'squaremap', 'radarmasksm')
    squareReady = true
end

-- The map's TRUE on-screen rect (pixels) for the current component pos + scale.
-- GetScriptGfxPosition applies the safe zone + aspect exactly, so the NUI frame
-- placed at this rect is always pixel-aligned with the native map.
local function getMinimapRect()
    local resX, resY = GetActiveScreenResolution()
    local aspect = GetAspectRatio(false)
    local big = IsBigmapActive()
    local w = (big and (1.0 / (2.52 * aspect)) or (1.0 / (4.0 * aspect))) * map.scale
    local h = (big and (1.0 / 2.3374) or (1.0 / 5.674)) * map.scale
    SetScriptGfxAlign(string.byte('L'), string.byte('B'))
    local leftX, topY = GetScriptGfxPosition(map.posX, map.posY - h)
    ResetScriptGfxAlign()
    return math.floor(leftX * resX + 0.5), math.floor(topY * resY + 0.5),
           math.floor(w * resX + 0.5), math.floor(h * resY + 0.5)
end

-- Push the qb-hud square layout (blip centred) at the current pos + scale.
local function applyMinimap()
    local s = map.scale
    pcall(function() SetMinimapClipType(0) end)
    SetMinimapComponentPosition('minimap',      'L', 'B', map.posX,            map.posY - 0.049 * s, 0.1638 * s, 0.183 * s)
    SetMinimapComponentPosition('minimap_mask', 'L', 'B', map.posX,            map.posY,             0.128 * s,  0.20 * s)
    SetMinimapComponentPosition('minimap_blur', 'L', 'B', map.posX - 0.01 * s, map.posY + 0.025 * s, 0.262 * s,  0.300 * s)
    SetBlipAlpha(GetNorthRadarBlip(), 0)
end

-- Single minimap loop: position the native map, strip the GTA:O health/armour
-- bars (scaleform), and slave the NUI frame to the map's true rect. Gated on
-- pause/menu state so nothing is drawn (or forced back on) over a menu.
CreateThread(function()
    while not loaded do Wait(200) end
    loadSquareMask()
    local mm = RequestScaleformMovie('minimap')
    local t = 0
    while not HasScaleformMovieLoaded(mm) and t < 200 do Wait(0); t = t + 1 end
    local lastR
    while true do
        if hudHidden or not minimapEnabled() then
            DisplayRadar(false)
            if lastR ~= false then lastR = false; SendNUIMessage({ action = 'minimap', hide = true }) end
            Wait(120)
        else
            DisplayRadar(true)
            retrySquareMask()   -- no-op once the mask is in; keeps retrying after a flaky restart
            applyMinimap()
            if HasScaleformMovieLoaded(mm) then
                BeginScaleformMovieMethod(mm, 'SETUP_HEALTH_ARMOUR')
                ScaleformMovieMethodAddParamInt(3)   -- GOLF mode = no bars
                EndScaleformMovieMethod()
            end
            local x, y, w, h = getMinimapRect()
            if not lastR or lastR.x ~= x or lastR.y ~= y or lastR.w ~= w or lastR.h ~= h then
                lastR = { x = x, y = y, w = w, h = h }
                SendNUIMessage({ action = 'minimap', rect = lastR })
            end
            Wait(0)
        end
    end
end)

-- ── Hide the whole HUD in menus (pause/ESC, map, fade, switch, our own NUIs) ──
local function shouldHideHud()
    return IsPauseMenuActive()
        or GetPauseMenuState() ~= 0        -- catches the open/close transition frames
        or IsScreenFadedOut()
        or IsScreenFadingOut()
        or IsPlayerSwitchInProgress()
        or GetIsLoadingScreenActive()
        or IsHudHidden()
        or (LocalPlayer.state.nuiOpen == true)   -- one of our NUI menus is open (v-core focus)
end

CreateThread(function()
    local hidden = nil
    while true do
        Wait(50)
        local hide = shouldHideHud()
        if hide ~= hidden then
            hidden = hide
            hudHidden = hide
            if hide then DisplayRadar(false) end
            SendNUIMessage({ action = 'visible', visible = not hide })
        end
    end
end)

-- Debounced KVP persist so minimap tweaks survive a relog even without Save.
local persistPending = false
local function persistSettings()
    if persistPending then return end
    persistPending = true
    SetTimeout(600, function()
        persistPending = false
        SetResourceKvpString('vhud:settings', json.encode(settings))
    end)
end

local function saveMap()
    settings.map = { posX = map.posX, posY = map.posY, scale = map.scale }
    persistSettings()
end

-- Drag the minimap: NUI reports a PIXEL delta -> 1:1 component delta (the gfx
-- transform is unit-slope, so this is exact). 'B' anchor flips Y.
RegisterNUICallback('mapDrag', function(data, cb)
    local rx, ry = GetActiveScreenResolution()
    if rx > 0 and ry > 0 and type(data.dx) == 'number' and type(data.dy) == 'number' then
        map.posX = map.posX + (data.dx / rx)
        map.posY = map.posY - (data.dy / ry)
        saveMap()
    end
    cb('ok')
end)

-- Resize the minimap (corner handle / size slider) via a single scale factor.
RegisterNUICallback('mapResize', function(data, cb)
    local sc = tonumber(data.scale)
    if sc then map.scale = math.min(2.0, math.max(0.5, sc)); saveMap() end
    cb('ok')
end)

-- Factory reset (F7 panel Reset button): bring the map back to the default
-- bottom-left dock — recovers a map dragged off-screen, which was unrecoverable
-- from the UI (KVP keeps the Lua-owned pos/scale across relogs).
RegisterNUICallback('mapReset', function(_, cb)
    map.posX, map.posY, map.scale = 0.0, 0.0, 1.0
    saveMap()
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
    if type(data) == 'table' then
        data.map = settings.map   -- preserve the Lua-owned minimap pos/scale
        settings = data
    end
    SetResourceKvpString('vhud:settings', json.encode(settings))
    SetNuiFocus(false, false)
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

-- ── Theme ──────────────────────────────────────────────────────
-- A NUI page can only be messaged by the resource that owns it, so v-ui cannot reach this
-- one directly: it publishes a version and each module forwards it into its own page.
local function pushTheme()
    if GetResourceState('v-ui') ~= 'started' then return end
    SendNUIMessage({ action = 'v-ui:theme', version = exports['v-ui']:Version() })
end

AddEventHandler('v-ui:client:themeChanged', function() pushTheme() end)
CreateThread(function() Wait(4000); pushTheme() end)
