-- v-banking | Français
Locales.fr = Locales.fr or {}
local T = {
    ['bank.help']        = 'Utiliser le distributeur',
    ['bank.title']       = 'Banque Fleeca',
    ['bank.balance']     = 'Solde du compte',
    ['bank.cash']        = 'Argent liquide',
    ['bank.deposit']     = 'Déposer',
    ['bank.withdraw']    = 'Retirer',
    ['bank.transfer']    = 'Virement',
    ['bank.amount']      = 'Montant',
    ['bank.target']      = 'ID du destinataire (citizen id)',
    ['bank.history']     = 'Activité récente',
    ['bank.confirm']     = 'Confirmer',
    ['bank.empty']       = 'Aucune transaction pour le moment.',
    ['bank.err_funds']   = 'Fonds insuffisants.',
    ['bank.err_target']  = 'Destinataire introuvable.',
    ['bank.ok_deposit']  = 'Dépôt de $%s effectué.',
    ['bank.ok_withdraw'] = 'Retrait de $%s effectué.',
    ['bank.ok_transfer'] = 'Virement de $%s effectué.',
    ['tx.deposit']       = 'Dépôt',
    ['tx.withdraw']      = 'Retrait',
    ['tx.transfer_in']   = 'Virement reçu',
    ['tx.transfer_out']  = 'Virement envoyé',
}
for k, v in pairs(T) do Locales.fr[k] = v end
