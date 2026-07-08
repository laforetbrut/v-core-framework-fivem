-- v-core | French strings
Locales.fr = Locales.fr or {}
local T = {
    ['core.welcome']     = 'Bienvenue sur %s, %s !',
    ['core.no_license']  = 'Aucun identifiant de licence trouvé.',
    ['hud.cash']         = 'Liquide',
    ['hud.bank']         = 'Banque',
    ['hud.health']       = 'Santé',
    ['hud.armor']        = 'Armure',
    ['hud.hunger']       = 'Faim',
    ['hud.thirst']       = 'Soif',
    ['hud.stress']       = 'Stress',
    ['hud.stamina']      = 'Endurance',
    ['hud.oxygen']       = 'Oxygène',
    ['hud.money']        = 'Argent',
}
for k, v in pairs(T) do Locales.fr[k] = v end
