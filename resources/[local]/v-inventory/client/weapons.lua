-- v-inventory | client weapon / ammo / armor handling
-- Item names ARE the GTA weapon hash names (e.g. 'weapon_assaultrifle'), so the
-- hash is GetHashKey(name). Ammo lives on the ped while a weapon is drawn and is
-- synced back to the item metadata on holster (and periodically, for safety).
local equipped = nil   -- { slot, name, hash }

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
    equipped = { slot = w.slot, name = w.name, hash = hash }
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

-- Persist the drawn weapon's live ammo even if the player never holsters.
CreateThread(function()
    while true do
        Wait(15000)
        if equipped then
            TriggerServerEvent('v-inventory:server:weaponAmmo', equipped.slot, GetAmmoInPedWeapon(PlayerPedId(), equipped.hash))
        end
    end
end)
