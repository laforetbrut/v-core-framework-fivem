-- v-inventory | client weapon / ammo / armor handling
-- Item names ARE the GTA weapon hash names (e.g. 'weapon_assaultrifle'), so the
-- hash is GetHashKey(name). Ammo lives on the ped while a weapon is drawn and is
-- synced back to the item metadata on holster (and periodically, for safety).
local Core = exports['v-core']:GetCore()
local equipped = nil   -- { slot, name, hash, dur }

local function strings()
    return Locales[(LocalPlayer.state and LocalPlayer.state.lang) or 'fr'] or Locales.fr or {}
end

RegisterNetEvent('v-inventory:client:equipWeapon', function(w)
    local ped = PlayerPedId()
    if IsEntityDead(ped) then return end
    if equipped then RemoveWeaponFromPed(ped, equipped.hash) end
    local hash = GetHashKey(w.name)
    GiveWeaponToPed(ped, hash, math.max(0, math.floor(w.ammo or 0)), false, true)
    -- Re-apply attachments stored on the weapon item (a map kind -> component name).
    if type(w.attachments) == 'table' then
        for _, comp in pairs(w.attachments) do
            GiveWeaponComponentToPed(ped, hash, GetHashKey(comp))
        end
    end
    SetCurrentPedWeapon(ped, hash, true)
    equipped = { slot = w.slot, name = w.name, hash = hash, dur = tonumber(w.durability) }
end)

-- Server pushes the weapon's current condition so jam odds stay accurate as it wears.
RegisterNetEvent('v-inventory:client:weaponCondition', function(slot, dur)
    if equipped and equipped.slot == slot then equipped.dur = tonumber(dur) end
end)

-- Fit a single component to the currently-drawn weapon (used right after crafting/using an attachment).
RegisterNetEvent('v-inventory:client:applyAttachment', function(comp)
    local ped = PlayerPedId()
    if equipped and comp then GiveWeaponComponentToPed(ped, equipped.hash, GetHashKey(comp)) end
end)

RegisterNetEvent('v-inventory:client:unequipWeapon', function(slot, name)
    local ped = PlayerPedId()
    local hash = GetHashKey(name)
    TriggerServerEvent('v-inventory:server:weaponAmmo', slot, GetAmmoInPedWeapon(ped, hash))
    RemoveWeaponFromPed(ped, hash)
    SetCurrentPedWeapon(ped, GetHashKey('weapon_unarmed'), true)
    if equipped and equipped.slot == slot then equipped = nil end
end)

RegisterNetEvent('v-inventory:client:giveAmmo', function(name, amount)
    AddAmmoToPed(PlayerPedId(), GetHashKey(name), math.max(0, math.floor(amount or 0)))
end)

RegisterNetEvent('v-inventory:client:applyArmor', function(amount)
    SetPedArmour(PlayerPedId(), math.max(0, math.min(100, math.floor(amount or 100))))
end)

-- ── Jamming ────────────────────────────────────────────────────
-- A worn weapon can jam on firing: the shot is blocked for a moment and a reload is
-- forced. Odds scale from 0 at the threshold up to JamMaxChance at 0% condition.
CreateThread(function()
    local wasShooting, jamUntil = false, 0
    while true do
        local wait = 500
        local dur = equipped and equipped.dur
        if dur and dur <= (Config.JamThreshold or 25) then
            wait = 0
            local ped = PlayerPedId()
            local now = GetGameTimer()
            if now < jamUntil then
                DisablePlayerFiring(PlayerId(), true)
                DisableControlAction(0, 24, true)   -- attack
                DisableControlAction(0, 257, true)  -- attack2
            else
                local shooting = IsPedShooting(ped)
                if shooting and not wasShooting then
                    local span = math.max(1, Config.JamThreshold or 25)
                    local chance = (Config.JamMaxChance or 0.18) * ((span - dur) / span)
                    if math.random() < chance then
                        jamUntil = now + (Config.JamBlockMs or 1300)
                        MakePedReload(ped)
                        PlaySoundFrontend(-1, 'Faux_Click', 'DLC_HEIST_BIOLAB_PREP_HACKING_SOUNDS', true)
                        Core.Notify(strings()['inv.jam'] or 'Weapon jammed!', 'error')
                    end
                end
                wasShooting = shooting
            end
        else
            wasShooting = false
        end
        Wait(wait)
    end
end)

-- Persist the drawn weapon's live ammo even if the player never holsters.
CreateThread(function()
    while true do
        Wait(15000)
        if equipped then
            TriggerServerEvent('v-inventory:server:weaponAmmo', equipped.slot, GetAmmoInPedWeapon(PlayerPedId(), equipped.hash))
        end
    end
end)

-- An admin changed a weapon tunable: the jam roll happens on the client, so it needs them.
RegisterNetEvent('v-inventory:client:tunables', function(t)
    if type(t) ~= 'table' then return end
    Config.JamThreshold = tonumber(t.jamThreshold) or Config.JamThreshold
    Config.JamMaxChance = tonumber(t.jamMaxChance) or Config.JamMaxChance
    Config.HotbarSlots  = tonumber(t.hotbarSlots) or Config.HotbarSlots
end)
