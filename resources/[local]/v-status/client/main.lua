-- v-status | client
-- Applies server-driven damage/effects and reports injuries. The HUD reads
-- this data via exports['v-status']:Get() and the v-status:client:onUpdate event.
local status = { hunger = 100, thirst = 100, stress = 0, bleed = 0, sick = 0 }

exports('Get', function() return status end)

RegisterNetEvent('v-status:client:update', function(s)
    status = s
    TriggerEvent('v-status:client:onUpdate', s)
end)

-- Server tells us to apply damage (starvation, bleed, illness).
RegisterNetEvent('v-status:client:damage', function(amount, floor)
    local ped = PlayerPedId()
    if IsEntityDead(ped) then return end
    local hp = GetEntityHealth(ped)
    local target = hp - (amount or 0)
    if floor and floor > 0 then target = math.max(floor, target) end
    if target < hp then
        SetEntityHealth(ped, math.max(101, target))
    end
end)

-- Bleeding visual feedback + occasional ragdoll at high levels.
RegisterNetEvent('v-status:client:bleedfx', function(level)
    local ped = PlayerPedId()
    StartScreenEffect('MinigameTransitionIn', 250, false)
    Citizen.SetTimeout(260, function() StopScreenEffect('MinigameTransitionIn') end)
    if level >= Config.BleedRagdollFrom and math.random(1, 3) == 1 then
        SetPedToRagdoll(ped, 1200, 1200, 0, false, false, false)
    end
end)

RegisterNetEvent('v-status:client:heal', function()
    ClearPedBloodDamage(PlayerPedId())
end)

-- ── Injury detection: notable damage -> bleed ──────────────────
CreateThread(function()
    local last = 200
    while true do
        Wait(1000)
        local ped = PlayerPedId()
        local hp = GetEntityHealth(ped)
        if hp > 100 and hp < (last - 8) then
            TriggerServerEvent('v-status:server:addBleed', 1)
        end
        last = hp
    end
end)

-- ── Respawn detection: reset bleed after death ─────────────────
CreateThread(function()
    local wasDead = false
    while true do
        Wait(1500)
        local dead = IsEntityDead(PlayerPedId())
        if wasDead and not dead then
            TriggerServerEvent('v-status:server:onRespawn')
        end
        wasDead = dead
    end
end)

-- ── Stress screen effects ──────────────────────────────────────
CreateThread(function()
    while true do
        Wait(1000)
        local s = status.stress or 0
        if s >= Config.StressShakeFrom then
            ShakeGameplayCam('SMALL_EXPLOSION_SHAKE', 0.06)
        end
        if s >= Config.StressBlurFrom then
            SetTimecycleModifier('Bank_ariel_amcop')  -- subtle desaturated tunnel feel
            SetTimecycleModifierStrength(0.35)
        else
            ClearTimecycleModifier()
        end
    end
end)
