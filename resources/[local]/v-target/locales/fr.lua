-- v-target | Français
-- Les chaînes contenant une apostrophe sont en guillemets doubles : une apostrophe dans
-- une chaîne Lua entre quotes simples ferme la chaîne.
Locales.fr = Locales.fr or {}
local T = {
    -- ── Ce que vise l'oeil (titre du panneau) ──
    ['tgt.lbl_player']    = 'Joueur',
    ['tgt.lbl_ped']       = 'Passant',
    ['tgt.lbl_vehicle']   = 'Véhicule',
    ['tgt.lbl_object']    = 'Objet',
    ['tgt.self']          = 'Vous-même',
    ['tgt.action']        = 'Action',

    -- ── Aides clavier du pied de panneau ──
    ['tgt.hint_nav']      = 'naviguer',
    ['tgt.hint_pick']     = 'valider',
    ['tgt.hint_close']    = 'fermer',

    -- ── Soi-même ──
    ['tgt.self_inv']          = 'Inventaire',
    ['tgt.self_hands']        = "Mains en l'air",
    ['tgt.self_vehicle']      = 'Commandes du véhicule',
    ['tgt.self_work']         = 'Travail',
    ['tgt.self_comms']        = 'Communications',
    ['tgt.self_leave_house']  = 'Sortir du logement',
    ['tgt.self_house_stash']  = 'Rangement du logement',
    ['tgt.self_admin']        = 'Menu administrateur',

    ['tgt.veh_engine']    = 'Moteur',
    ['tgt.veh_left']      = 'Clignotant gauche',
    ['tgt.veh_right']     = 'Clignotant droit',
    ['tgt.veh_haz']       = 'Feux de détresse',
    ['tgt.veh_seat']      = 'Changer de place',
    ['tgt.veh_belt']      = 'Ceinture',
    ['tgt.veh_lock']      = 'Verrouiller / déverrouiller',

    ['tgt.work_boss']     = "Gestion de l'entreprise",
    ['tgt.work_police']   = 'Terminal police',
    ['tgt.comms_radio']   = 'Radio',
    ['tgt.comms_music']   = 'Musique',

    -- ── Véhicules ──
    ['tgt.trunk']         = 'Ouvrir le coffre',
    ['tgt.glovebox']      = 'Ouvrir la boîte à gants',
    ['tgt.doors']         = 'Ouvrir / fermer les portières',
    ['tgt.door_one']      = 'Ouvrir / fermer cette portière',
    ['tgt.hood']          = 'Ouvrir / fermer le capot',
    ['tgt.boot']          = 'Ouvrir / fermer le hayon',
    ['tgt.engine']        = 'Moteur',
    ['tgt.enter_seat']    = 'Monter',
    ['tgt.lock']          = 'Verrouiller / déverrouiller',
    ['tgt.lockpick']      = 'Forcer la serrure',
    ['tgt.flip']          = 'Remettre sur ses roues',
    ['tgt.diagnose']      = 'Diagnostiquer',
    ['tgt.impound']       = 'Mettre en fourrière',
    ['tgt.repair']        = 'Réparer',
    ['tgt.clean']         = 'Nettoyer',

    -- ── Personnes ──
    ['tgt.frisk']         = 'Fouiller',
    ['tgt.police']        = 'Police',
    ['tgt.police_search'] = 'Fouille policière',
    ['tgt.pol_cuff']      = 'Menotter / démenotter',
    ['tgt.pol_escort']    = 'Escorter',
    ['tgt.pol_search']    = 'Fouiller le suspect',

    -- ── Administration ──
    ['tgt.a_player']      = 'Modération',
    ['tgt.a_vehicle']     = 'Modération',
    ['tgt.a_heal']        = 'Soigner',
    ['tgt.a_freeze']      = 'Figer',
    ['tgt.a_unfreeze']    = 'Libérer',
    ['tgt.a_bring']       = 'Amener ici',
    ['tgt.a_goto']        = 'Se téléporter',
    ['tgt.a_spectate']    = 'Observer',
    ['tgt.a_inv']         = "Ouvrir l'inventaire",
    ['tgt.a_unlock']      = 'Déverrouillage forcé',
    ['tgt.a_plate']       = 'Lire la plaque',
    ['tgt.a_ped_del']     = 'Supprimer ce PNJ',

    -- ── Enregistrées par d'autres modules ──
    ['tgt.shop']          = 'Consulter la boutique',
    ['tgt.vending']       = 'Distributeur',
    ['tgt.dealer']        = 'Parler au dealer',
    ['tgt.launder']       = "Blanchir de l'argent",
    ['tgt.scrap']         = 'Vendre des matériaux',
    ['tgt.cityhall']      = 'Guichet emploi',

    -- ── Pourquoi une action est refusée ──
    -- Affiché sous une ligne grisée : chacune doit dire ce qui la débloquerait.
    ['tgt.need_item']     = 'Il vous manque le bon outil',
    ['tgt.err_x']         = 'Impossible pour le moment',
    ['tgt.err_denied']    = 'Refusé',
    ['tgt.err_notnet']    = "Ce véhicule n'est pas encore synchronisé",
    ['tgt.err_locked']    = "C'est verrouillé",
    ['tgt.err_unlocked']  = "C'est déjà déverrouillé",
    ['tgt.err_occupied']  = 'Cette place est occupée',
    ['tgt.err_notcop']    = 'Réservé à la police',
    ['tgt.err_far']       = 'Trop loin',
    ['tgt.err_noitem']    = 'Il vous manque le bon outil',
    ['tgt.err_notcuffed'] = 'Il faut le menotter avant',
    ['tgt.err_novehicle'] = 'Aucun véhicule ici',
    ['tgt.err_unknown']   = 'Ce véhicule est inconnu au fichier',
    ['tgt.err_off']       = 'Désactivé sur ce serveur',
}
for k, v in pairs(T) do Locales.fr[k] = v end
