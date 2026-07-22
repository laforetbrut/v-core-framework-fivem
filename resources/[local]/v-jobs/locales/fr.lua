-- v-jobs | Français
Locales.fr = Locales.fr or {}
local T = {
    ['jobs.paid']  = 'Salaire : $%s.',
    ['jobs.set']   = 'Métier défini : %s — %s.',
    ['jobs.usage'] = 'Usage : setjob <idJoueur> <idMetier> [grade].',
    ['jobs.nopay'] = "Votre employeur n'a pas pu payer les salaires.",
}
for k, v in pairs(T) do Locales.fr[k] = v end
