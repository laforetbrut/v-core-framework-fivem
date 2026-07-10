-- v-crafting | Français
Locales.fr = Locales.fr or {}
local T = {
    ['craft.help']    = 'Fabriquer',
    ['craft.sub']     = 'Choisis une recette · il te faut tous les matériaux',
    ['craft.make']    = 'Fabriquer',
    ['craft.done']    = 'Fabriqué %sx %s.',
    ['craft.missing'] = 'Matériaux manquants.',
    ['craft.nospace'] = 'Pas assez de place dans l\'inventaire.',
    ['craft.too_far'] = 'Rapproche-toi de l\'établi.',
    ['craft.locked']  = 'Tu ne peux pas fabriquer ça ici.',
}
for k, v in pairs(T) do Locales.fr[k] = v end
