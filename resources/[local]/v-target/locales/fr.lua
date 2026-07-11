-- v-target | Français
Locales.fr = Locales.fr or {}
local T = {
    ['tgt.trunk']         = 'Ouvrir le coffre',
    ['tgt.glovebox']      = 'Ouvrir la boîte à gants',
    ['tgt.doors']         = 'Ouvrir / fermer les portières',
    ['tgt.hood']          = 'Ouvrir / fermer le capot',
    ['tgt.boot']          = 'Ouvrir / fermer le hayon',
    ['tgt.engine']        = 'Moteur on / off',
    ['tgt.lock']          = 'Verrouiller / déverrouiller',
    ['tgt.flip']          = 'Remettre le véhicule',
    ['tgt.repair']        = 'Réparer le véhicule',
    ['tgt.clean']         = 'Nettoyer le véhicule',
    ['tgt.frisk']         = 'Fouiller',
    ['tgt.police_search'] = 'Fouiller le suspect',
    ['tgt.a_heal']        = 'Soigner (admin)',
    ['tgt.a_freeze']      = 'Geler (admin)',
    ['tgt.a_unfreeze']    = 'Dégeler (admin)',
    ['tgt.a_bring']       = 'Amener ici (admin)',
    ['tgt.a_goto']        = 'Se téléporter à (admin)',
    ['tgt.a_spectate']    = 'Observer (admin)',
    ['tgt.a_inv']         = 'Ouvrir l\'inventaire (admin)',
}
for k, v in pairs(T) do Locales.fr[k] = v end
