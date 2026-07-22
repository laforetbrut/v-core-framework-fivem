-- v-music | Français
Locales.fr = Locales.fr or {}
local T = {
    ['mus.title']    = 'Musique',
    ['mus.boombox']  = 'Enceinte',
    ['mus.vehicle']  = 'Autoradio',
    ['mus.jukebox']  = 'Juke-box',
    ['mus.playing']  = 'En lecture',
    ['mus.play']     = 'Lire',
    ['mus.pause']    = 'Pause',
    ['mus.resume']   = 'Reprendre',
    ['mus.stop']     = 'Arrêter',
    ['mus.url']      = 'Collez un lien',
    ['mus.none']     = 'Rien en lecture.',
    ['mus.hint']     = 'Seuls les liens des hôtes autorisés par le serveur seront lus.',
    ['mus.err_off']       = 'La musique est désactivée sur ce serveur.',
    ['mus.err_host']      = "Cet hôte n'est pas autorisé ici.",
    ['mus.err_noitem']    = "Vous n'avez pas d'enceinte.",
    ['mus.err_toomany']   = 'Vous en avez déjà une posée.',
    ['mus.err_novehicle'] = "Vous n'êtes pas dans un véhicule.",
    ['mus.err_nokeys']    = "Vous n'avez pas les clés.",
    ['mus.err_nosource']  = 'Rien à contrôler ici.',
    ['mus.err_notyours']  = "Ce n'est pas à vous de le contrôler.",
    ['mus.err_far']       = 'Vous êtes trop loin.',
    ['mus.err_x']         = 'Une erreur est survenue.',
}
for k, v in pairs(T) do Locales.fr[k] = v end
