-- v-phone | Français
-- Les chaînes contenant une apostrophe sont en guillemets doubles : une apostrophe dans
-- une chaîne Lua entre quotes simples ferme la chaîne.
Locales.fr = Locales.fr or {}
local T = {
    -- ── Noms des applications (écran d'accueil) ──
    ['app.phone']    = 'Téléphone',
    ['app.messages'] = 'Messages',
    ['app.contacts'] = 'Contacts',
    ['app.bank']     = 'Banque',
    ['app.garage']   = 'Garage',
    ['app.wallet']   = 'Portefeuille',
    ['app.jobs']     = 'Emplois',
    ['app.settings'] = 'Réglages',
    ['app.camera']   = 'Appareil photo',

    -- ── Commun ──
    ['ph.loading']   = 'Chargement',
    ['ph.save']      = 'Enregistrer',
    ['ph.delete']    = 'Supprimer',
    ['ph.send']      = 'Envoyer',
    ['ph.call']      = 'Appeler',
    ['ph.message']   = 'Message',
    ['ph.name']      = 'Nom',
    ['ph.number']    = 'Numéro',
    ['ph.on']        = 'Activé',
    ['ph.no_app']    = "Cette application n'a encore rien à afficher",

    -- ── Messages et contacts ──
    ['ph.write']        = 'Écrire un message',
    ['ph.no_messages']  = 'Aucune conversation',
    ['ph.no_contacts']  = 'Aucun contact',
    ['ph.contacts']     = 'Contacts',
    ['ph.new_contact']  = 'Nouveau contact',
    ['ph.new_message']  = 'Nouveau message de %s',

    -- ── Appels ──
    ['ph.incoming']     = 'Appel entrant',
    ['ph.calling']      = 'Appel en cours',
    ['ph.in_call']      = 'En communication',
    ['ph.unknown']      = 'Numéro masqué',
    ['ph.call_noanswer'] = 'Pas de réponse',
    ['ph.call_timeout'] = "Appel terminé : il a trop duré",
    ['ph.call_dropped'] = "Votre correspondant s'est déconnecté",
    ['ph.call_hangup']  = 'Appel terminé',

    -- ── Banque ──
    ['ph.balance']      = 'Solde du compte',
    ['ph.cash']         = 'Liquide',
    ['ph.history']      = 'Activité récente',
    ['ph.no_history']   = 'Aucune activité',

    -- ── Garage ──
    ['ph.no_vehicles']  = 'Aucun véhicule à votre nom',
    ['ph.veh_out']      = 'Sorti',
    ['ph.veh_stored']   = 'Garé',
    ['ph.out']          = 'Dans la rue',

    -- ── Portefeuille ──
    ['ph.no_licenses']  = 'Aucun permis enregistré',
    ['ph.lic_held']     = 'Détenu',
    ['ph.lic_none']     = 'Aucun',

    -- ── Emplois ──
    ['ph.current_job']  = 'Emploi actuel',
    ['ph.openings']     = 'Postes ouverts',
    ['ph.no_jobs']      = 'Rien de proposé pour le moment',
    ['ph.jobs_hint']    = "Rendez-vous à la mairie pour signer",

    -- ── Réglages ──
    ['ph.my_number']    = 'Mon numéro',
    ['ph.wallpaper']    = "Fond d'écran",
    ['ph.wall_dune']    = 'Dune',
    ['ph.wall_grid']    = 'Grille',
    ['ph.wall_night']   = 'Nuit',
    ['ph.wall_ember']   = 'Braise',
    ['ph.dnd']          = 'Ne pas déranger',
    ['ph.dnd_on']       = 'Ne pas déranger activé',
    ['ph.dnd_off']      = 'Ne pas déranger désactivé',

    -- ── Erreurs ──
    ['ph.err_x']        = "Quelque chose s'est mal passé",
    ['ph.err_off']      = "Indisponible sur ce serveur",
    ['ph.err_nophone']  = "Vous n'avez pas de téléphone sur vous",
    ['ph.err_nonumber'] = "Ce numéro n'existe pas",
    ['ph.err_self']     = "C'est votre propre numéro",
    ['ph.err_empty']    = "Écrivez quelque chose d'abord",
    ['ph.err_busy']     = 'Vous êtes déjà en communication',
    ['ph.err_busy_them'] = 'La ligne est occupée',
    ['ph.err_offline']  = 'Son téléphone est éteint',
    ['ph.err_dnd']      = 'Cette personne ne prend pas les appels',
    ['ph.err_fields']   = 'Un nom et un numéro sont nécessaires',
    ['ph.err_unknown']  = 'Application inconnue',
    ['ph.home'] = 'Accueil',
    ['ph.unread'] = 'Non lus',
    ['ph.mute'] = 'muet',
    ['ph.keypad'] = 'clavier',
    ['ph.speaker'] = 'haut-parleur',
    ['ph.new_message_to'] = 'Nouveau message',
    ['ph.dnd_hint'] = 'Les appels sont refusés et les messages arrivent sans bannière.',
    ['ph.camera_off'] = "L'appareil photo est désactivé sur ce serveur",
    ['ph.torch_hint'] = 'Rien à éclairer ici',
}
for k, v in pairs(T) do Locales.fr[k] = v end
