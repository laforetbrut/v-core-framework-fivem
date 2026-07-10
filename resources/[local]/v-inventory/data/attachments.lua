-- v-inventory | weapon-attachment component map (server)
-- Maps a generic attachment kind (suppressor / flashlight / scope / grip / extclip)
-- to the GTA weapon-component name for a specific weapon. A kind that has no entry
-- for the drawn weapon simply "doesn't fit" — safe default for addon weapons whose
-- component hashes we can't know. The client hashes the returned component name.
WeaponComponents = {
    weapon_pistol = {
        suppressor = 'COMPONENT_AT_PI_SUPP_02',
        flashlight = 'COMPONENT_AT_PI_FLSH',
        extclip    = 'COMPONENT_PISTOL_CLIP_02',
    },
    weapon_appistol = {
        suppressor = 'COMPONENT_AT_PI_SUPP',
        flashlight = 'COMPONENT_AT_PI_FLSH',
        extclip    = 'COMPONENT_APPISTOL_CLIP_02',
    },
    weapon_combatpistol = {
        suppressor = 'COMPONENT_AT_PI_SUPP',
        flashlight = 'COMPONENT_AT_PI_FLSH',
        extclip    = 'COMPONENT_COMBATPISTOL_CLIP_02',
    },
    weapon_assaultrifle = {
        suppressor = 'COMPONENT_AT_AR_SUPP_02',
        flashlight = 'COMPONENT_AT_AR_FLSH',
        scope      = 'COMPONENT_AT_SCOPE_MACRO',
        grip       = 'COMPONENT_AT_AR_AFGRIP',
        extclip    = 'COMPONENT_ASSAULTRIFLE_CLIP_02',
    },
    weapon_advancedrifle = {
        suppressor = 'COMPONENT_AT_AR_SUPP',
        flashlight = 'COMPONENT_AT_AR_FLSH',
        scope      = 'COMPONENT_AT_SCOPE_SMALL',
        extclip    = 'COMPONENT_ADVANCEDRIFLE_CLIP_02',
    },
    weapon_carbinerifle = {
        suppressor = 'COMPONENT_AT_AR_SUPP',
        flashlight = 'COMPONENT_AT_AR_FLSH',
        scope      = 'COMPONENT_AT_SCOPE_MEDIUM',
        grip       = 'COMPONENT_AT_AR_AFGRIP',
        extclip    = 'COMPONENT_CARBINERIFLE_CLIP_02',
    },
    weapon_smg = {
        suppressor = 'COMPONENT_AT_PI_SUPP',
        flashlight = 'COMPONENT_AT_AR_FLSH',
        scope      = 'COMPONENT_AT_SCOPE_MACRO_02',
        extclip    = 'COMPONENT_SMG_CLIP_02',
    },
    weapon_pumpshotgun = {
        flashlight = 'COMPONENT_AT_AR_FLSH',
    },
}

-- Component name for (weapon, kind), or nil when the kind doesn't fit that weapon.
function ComponentFor(weaponName, kind)
    local w = WeaponComponents[weaponName]
    return w and w[kind] or nil
end
