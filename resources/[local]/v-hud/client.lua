-- v-hud | client
-- Reads money from v-core and mirrors it in the NUI HUD.

local function currentMoney()
    local data = exports['v-core']:GetPlayerData()
    return (data and data.money) or { cash = 0, bank = 0 }
end

-- Show the HUD once the player is fully loaded.
AddEventHandler('v-core:client:onPlayerLoaded', function(data)
    SendNUIMessage({ action = 'show', cash = data.money.cash, bank = data.money.bank })
end)

-- Live money updates (deposit, purchase, payday, ...).
AddEventHandler('v-core:client:onMoneyChange', function(money)
    SendNUIMessage({ action = 'money', cash = money.cash, bank = money.bank })
end)

-- If v-hud is (re)started mid-session, restore it with the current data.
CreateThread(function()
    Wait(800)
    local core = exports['v-core']:GetCore()
    if core and core.isLoaded then
        local m = currentMoney()
        SendNUIMessage({ action = 'show', cash = m.cash, bank = m.bank })
    end
end)
