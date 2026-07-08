-- v-hud | client
-- Feeds the NUI with money (v-core) + vitals (native + v-status), and
-- persists per-player HUD customization via KVP.

local loaded = false
local settings = nil

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

-- Push settings to the NUI as soon as it's ready.
CreateThread(function()
    loadSettings()
    Wait(250)
    SendNUIMessage({ action = 'init', settings = settings or {} })
end)

-- ── Money ──
AddEventHandler('v-core:client:onPlayerLoaded', function(data)
    loaded = true
    SendNUIMessage({ action = 'money', cash = data.money.cash, bank = data.money.bank })
end)

AddEventHandler('v-core:client:onMoneyChange', function(money)
    SendNUIMessage({ action = 'money', cash = money.cash, bank = money.bank, flash = true })
end)

-- ── Vitals poll ──
CreateThread(function()
    while true do
        Wait(350)
        if loaded then
            local ped = PlayerPedId()
            local pid = PlayerId()
            local s = status()
            local underwater = IsPedSwimmingUnderWater(ped)
            SendNUIMessage({ action = 'vitals', data = {
                health  = math.max(0, math.min(100, GetEntityHealth(ped) - 100)),
                armor   = GetPedArmour(ped),
                hunger  = s.hunger or 100,
                thirst  = s.thirst or 100,
                stress  = s.stress or 0,
                stamina = math.max(0, math.min(100, 100 - GetPlayerSprintStaminaRemaining(pid))),
                oxygen  = underwater and math.floor(GetPlayerUnderwaterTimeRemaining(pid) * 12) or 100,
                underwater = underwater,
            } })
        end
    end
end)

-- ── Settings (keybind, no chat command for players) ──
RegisterCommand('vhud_settings', function()
    if not loaded then return end
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'openSettings' })
end, false)
RegisterKeyMapping('vhud_settings', 'Open HUD settings', 'keyboard', 'F7')

RegisterNuiCallback('saveSettings', function(data, cb)
    settings = data
    SetResourceKvpString('vhud:settings', json.encode(data))
    SetNuiFocus(false, false)
    cb('ok')
end)

RegisterNuiCallback('closeSettings', function(_, cb)
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
