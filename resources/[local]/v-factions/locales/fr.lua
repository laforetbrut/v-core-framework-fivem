-- v-factions | Français
Locales.fr = Locales.fr or {}
local T = {
    ['fac.treasury']      = 'Trésorerie',
    ['fac.balance']       = 'Solde',
    ['fac.deposit']       = 'Dépôt',
    ['fac.withdraw']      = 'Retrait',
    ['fac.salary']        = 'Salaire',
    ['fac.members']       = 'Membres',
    ['fac.boss']          = 'Patron',
    ['fac.hired']         = 'Recruté.',
    ['fac.fired']         = 'Renvoyé.',
    ['fac.graded']        = 'Rang modifié.',
    ['fac.paid']          = 'Salaire payé depuis la trésorerie.',
    ['fac.nopay']         = 'La trésorerie n\'a pas pu couvrir les salaires.',
    ['fac.err_rank']      = 'Votre rang ne le permet pas.',
    ['fac.err_faction']   = 'Cette organisation n\'existe pas.',
    ['fac.err_target']    = 'Membre introuvable.',
    ['fac.err_grade']     = 'Ce rang n\'existe pas.',
    ['fac.err_funds']     = 'La trésorerie est insuffisante.',
    ['fac.err_limit']     = 'Cela dépasse la limite de retrait.',
    ['fac.err_amount']    = 'Saisissez un montant.',
    ['fac.err_disabled']  = 'Les trésoreries sont désactivées sur ce serveur.',
}
for k, v in pairs(T) do Locales.fr[k] = v end
