-- v-inventory | Français
Locales.fr = Locales.fr or {}
local T = {
    ['inv.title']      = 'Inventaire',
    ['inv.weight']     = 'Poids',
    ['inv.use']        = 'Utiliser',
    ['inv.give']       = 'Donner',
    ['inv.drop']       = 'Jeter',
    ['inv.amount']     = 'Quantité',
    ['inv.confirm']    = 'Confirmer',
    ['inv.cancel']     = 'Annuler',
    ['inv.trunk']      = 'Coffre',
    ['inv.glovebox']   = 'Boîte à gants',
    ['inv.stash']      = 'Stockage',
    ['inv.ground']     = 'Sol',
    ['inv.empty']      = 'Vide',
    ['inv.full']       = 'Pas assez de place.',
    ['inv.no_target']  = 'Personne à proximité.',
    ['inv.gave']       = 'Donné %sx %s.',
    ['inv.received']   = 'Reçu %sx %s.',
    ['inv.used']       = 'Utilisé %s.',
    ['inv.help_trunk'] = 'Ouvrir le coffre',
}
for k, v in pairs(T) do Locales.fr[k] = v end
