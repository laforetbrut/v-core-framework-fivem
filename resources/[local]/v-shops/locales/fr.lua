-- v-shops | Français
Locales.fr = Locales.fr or {}
local T = {
    ['shop.help']    = 'Parcourir la boutique',
    ['shop.buy']     = 'Acheter',
    ['shop.cash']    = 'Liquide',
    ['shop.bank']    = 'Banque',
    ['shop.total']   = 'Total',
    ['shop.each']    = 'l\'unité',
    ['shop.bought']  = 'Acheté %sx %s pour $%s.',
    ['shop.nofunds'] = 'Pas assez d\'argent.',
    ['shop.nospace'] = 'Pas assez de place dans l\'inventaire.',
    ['shop.too_far'] = 'Tu es trop loin de la boutique.',
    ['shop.no_job']  = 'Cette boutique est réservée à un métier.',
    ['shop.blip']    = 'Boutique',
    ['shop.inventory'] = 'Inventaire',
    ['shop.drag_hint'] = 'Glissez un article ici pour l\'acheter',
}
for k, v in pairs(T) do Locales.fr[k] = v end
