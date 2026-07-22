-- v-housing | Français
Locales.fr = Locales.fr or {}
local T = {
    ['house.blip']      = 'Propriété',
    ['house.door']      = 'Porte',
    ['house.leave']     = 'Sortir',
    ['house.stash']     = 'Rangement',
    ['house.inside']    = 'Vous êtes à l\'intérieur.',
    ['house.bought']    = 'Acheté pour %s $.',
    ['house.rented']    = 'Loué pour %s $.',
    ['house.rent_paid'] = 'Loyer payé : %s $.',
    ['house.got_key']   = 'On vous a remis une clé.',
    ['house.err_off']       = 'Les propriétés sont désactivées sur ce serveur.',
    ['house.err_noprop']    = 'Aucune propriété ici.',
    ['house.err_far']       = 'Vous êtes trop loin de la porte.',
    ['house.err_taken']     = 'Quelqu\'un habite déjà ici.',
    ['house.err_toomany']   = 'Vous détenez déjà le maximum de propriétés.',
    ['house.err_funds']     = 'Vous ne pouvez pas vous le permettre.',
    ['house.err_notyours']  = 'Ce n\'est pas chez vous.',
    ['house.err_nokey']     = 'Vous n\'avez pas de clé.',
    ['house.err_locked']    = 'La serrure a été changée : le loyer est en retard.',
    ['house.err_notinside'] = 'Vous n\'êtes pas dans une propriété.',
    ['house.err_notarget']  = 'Personne ici.',
    ['house.err_x']         = 'Une erreur est survenue.',
}
for k, v in pairs(T) do Locales.fr[k] = v end
