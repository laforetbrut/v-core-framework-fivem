-- v-radio | Français
Locales.fr = Locales.fr or {}
local T = {
    ['radio.title']     = 'Radio',
    ['radio.sub']       = 'À l\'écoute',
    ['radio.available'] = 'Canaux disponibles',
    ['radio.presets']   = 'Présélections',
    ['radio.listening'] = 'écoute',
    ['radio.talking']   = 'émission',
    ['radio.talkon']    = 'Émettre ici',
    ['radio.leave']     = 'Quitter',
    ['radio.leaveall']  = 'Éteindre',
    ['radio.save']      = 'Enregistrer ici',
    ['radio.empty']     = 'vide',
    ['radio.none']      = 'Aucun canal accessible.',
    ['radio.err_noradio']     = "Vous n'avez pas de radio sur vous.",
    ['radio.err_off']         = 'La radio est désactivée sur ce serveur.',
    ['radio.err_full']        = 'Cette radio ne suit que %s canaux.',
    ['radio.err_notyours']    = "Ce canal ne vous est pas destiné.",
    ['radio.err_grade']       = "Votre rang n'atteint pas ce canal.",
    ['radio.err_nochannel']   = "Ce canal n'existe pas.",
    ['radio.err_notlistening'] = "Vous ne suivez pas ce canal.",
    ['radio.err_x']           = 'Une erreur est survenue.',
}
for k, v in pairs(T) do Locales.fr[k] = v end
