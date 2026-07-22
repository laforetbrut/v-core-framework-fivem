-- v-voice | Français
Locales.fr = Locales.fr or {}
local T = {
    ['voice.whisper']  = 'Chuchoter',
    ['voice.normal']   = 'Normal',
    ['voice.shout']    = 'Crier',
    ['voice.now']      = 'Voix : %s',
    ['voice.joined']   = 'Canal radio %s.',
    ['voice.left']     = 'Radio coupée.',
    ['voice.muted']    = 'Vous avez été rendu muet.',
    ['voice.err_off']       = 'La radio est désactivée sur ce serveur.',
    ['voice.err_noradio']   = "Vous n'avez pas de radio sur vous.",
    ['voice.err_nochannel'] = "Ce canal n'existe pas.",
    ['voice.err_notyours']  = "Ce canal ne vous est pas destiné.",
    ['voice.err_grade']     = "Votre rang n'atteint pas ce canal.",
    ['voice.err_x']         = 'Une erreur est survenue.',
}
for k, v in pairs(T) do Locales.fr[k] = v end
