-- v-hud | Français
Locales.fr = Locales.fr or {}
local T = {
    ['hud.cash']     = 'Liquide',
    ['hud.bank']     = 'Banque',
    ['set.title']    = 'Réglages',
    ['set.elements'] = 'Éléments',
    ['set.accent']   = 'Accent',
    ['set.opacity']  = 'Opacité',
    ['set.scale']    = 'Taille',
    ['set.dynamic']  = 'Masquer si plein',
    ['set.reset']    = 'Réinit.',
    ['set.save']     = 'Sauver',
    ['el.health']    = 'Santé',
    ['el.armor']     = 'Armure',
    ['el.hunger']    = 'Faim',
    ['el.thirst']    = 'Soif',
    ['el.stress']    = 'Stress',
    ['el.stamina']   = 'Endurance',
    ['el.oxygen']    = 'Oxygène',
    ['el.money']     = 'Argent',
}
for k, v in pairs(T) do Locales.fr[k] = v end
