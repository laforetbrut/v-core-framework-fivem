-- v-jobs | Français
Locales.fr = Locales.fr or {}
local T = {
    ['jobs.paid']  = 'Salaire : $%s.',
    ['jobs.set']   = 'Métier défini : %s — %s.',
    ['jobs.usage'] = 'Usage : setjob <idJoueur> <idMetier> [grade].',
}
for k, v in pairs(T) do Locales.fr[k] = v end
