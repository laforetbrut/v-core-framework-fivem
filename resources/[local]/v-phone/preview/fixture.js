(function () {
  var strings = {
    'ph.back': 'Retour', 'ph.continue': 'Continuer',
    'ph.setup_hello': 'Bonjour',
    'ph.setup_intro': 'Quelques étapes suffisent pour faire de cet iFruit le vôtre.',
    'ph.setup_start': 'Configurer', 'ph.setup_identity': 'Faisons connaissance',
    'ph.setup_identity_hint': 'Ces noms apparaîtront dans Réglages, le centre de contrôle et FruitDrop.',
    'ph.setup_your_name': 'Votre nom', 'ph.setup_name_placeholder': 'Prénom et nom',
    'ph.setup_phone_name': 'Nom de l’iFruit', 'ph.setup_default_device': 'iFruit',
    'ph.setup_device_pattern': 'iFruit de {name}',
    'ph.setup_name_required': 'Renseignez les deux noms pour continuer.',
    'ph.setup_appearance': 'Choisissez une apparence',
    'ph.setup_appearance_hint': 'Vous pourrez la modifier à tout moment dans Réglages.',
    'ph.setup_personalise': 'Personnalisez votre iFruit',
    'ph.setup_personalise_hint': 'Choisissez un fond et ajustez la transparence Clear Glass.',
    'ph.setup_passcode': 'Créez un code',
    'ph.setup_passcode_hint': 'Ce code à 6 chiffres protège vos messages, vos photos et vos applications.',
    'ph.setup_passcode_confirm': 'Confirmez votre code',
    'ph.setup_passcode_confirm_hint': 'Saisissez une nouvelle fois les 6 chiffres.',
    'ph.setup_passcode_mismatch': 'Les deux codes ne correspondent pas.',
    'ph.setup_faceid': 'Configurer Face ID',
    'ph.setup_faceid_hint': 'Face ID reconnaît votre personnage et déverrouille iFruit en un regard.',
    'ph.setup_faceid_private': 'Vos données faciales restent liées à votre personnage.',
    'ph.setup_faceid_enrol': 'Commencer la reconnaissance',
    'ph.setup_faceid_scanning': 'Reconnaissance en cours…',
    'ph.setup_faceid_ready': 'Face ID est configuré',
    'ph.setup_faceid_redo': 'Recommencer', 'ph.setup_code_only': 'Utiliser uniquement le code',
    'ph.setup_ready': 'Votre iFruit est prêt',
    'ph.setup_ready_hint': '{device} est configuré et prêt à être utilisé.',
    'ph.setup_finish': 'Commencer', 'ph.setup_saving': 'Activation…',
    'ph.setup_retry': 'Réessayer', 'ph.setup_complete': 'Configuration terminée',
    'ph.faceid': 'Face ID', 'ph.faceid_recognising': 'Reconnaissance en cours…',
    'ph.faceid_recognised': 'Visage reconnu', 'ph.faceid_failed': 'Face ID indisponible',
    'ph.use_faceid': 'Utiliser Face ID', 'ph.use_passcode': 'Utiliser le code',
    'ph.enter_passcode': 'Saisissez votre code',
    'ph.passcode_unlock_hint': 'Entrez les 6 chiffres pour déverrouiller iFruit.',
    'ph.wrong_passcode': 'Code incorrect. Réessayez.',
    'ph.passcode_locked': 'Trop de tentatives. Réessayez dans {seconds} s.',
    'ph.passcode_progress': '{count} chiffre(s) saisi(s) sur 6',
    'ph.delete_digit': 'Effacer le dernier chiffre',
    'ph.faceid_and_passcode': 'Face ID et code', 'ph.passcode_enabled': 'Code à 6 chiffres',
    'ph.security_ready': 'Protection du verrouillage activée', 'ph.cancel': 'Annuler',
    'ph.theme_light': 'Clair', 'ph.theme_dark': 'Sombre', 'ph.theme_auto': 'Automatique',
    'ph.theme_auto_hint': "En automatique, l’écran passe en sombre la nuit selon l’heure du jeu.",
    'ph.wall_ifruit': 'iFruit', 'ph.wall_aurora': 'Aurore', 'ph.wall_lagoon': 'Lagon',
    'ph.glass_clear': 'Très clair', 'ph.glass_tinted': 'Plus teinté',
    'ph.home': 'Accueil', 'ph.search': 'Rechercher', 'ph.search_apps': 'Rechercher des apps',
    'ph.my_number': 'Mon numéro', 'ph.grid': 'Grille de l’écran d’accueil',
    'ph.dark_mode': 'Apparence', 'ph.vibrate': 'Vibrations', 'ph.ringer': 'Sonnerie',
    'ph.ringtone': 'Sonnerie', 'ph.alerttone': 'Son des alertes',
    'ph.tone_classic': 'Classique', 'ph.tone_ping': 'Ping', 'ph.fit_cover': 'Remplir',
    'ph.fit_contain': 'Ajuster', 'ph.wall_apply': 'Utiliser cette image',
    'ph.wall_url': 'Lien de l’image',
    'ph.wall_hint': 'Seuls les hébergeurs d’images autorisés par votre serveur se chargeront.',
    'ph.wallpaper': "Fond d'écran", 'ph.on': 'Activé', 'ph.device': 'Appareil',
    'ph.no_notes': 'Aucune note', 'ph.no_reminders': 'Rien à retenir',
    'ph.balance': 'Solde du compte', 'ph.cash': 'Liquide',
    'ph.no_history': 'Aucune activité', 'ph.no_vehicles': 'Aucun véhicule à votre nom',
    'ph.no_property': 'Vous ne louez et ne possédez rien',
    'ph.no_card': 'Aucune carte bancaire',
    'ph.no_card_hint': 'Commandez-en une à une banque ou un distributeur.',
    'ph.no_licenses': 'Aucun permis enregistré',
    'ph.unemployed': 'Sans emploi',
    'ph.unemployed_hint': 'Passez à la mairie ou consultez les offres pour trouver un poste.',
    'ph.warrants': 'Mandats', 'ph.lookup': 'Recherche',
    'ph.no_warrants': 'Aucun mandat actif',
    'ph.size': 'Taille', 'ph.side_right': 'Droite', 'ph.side_left': 'Gauche',
    'ph.dnd': 'Ne pas déranger',
    'ph.dnd_hint': 'Les appels sont refusés et les messages arrivent sans bannière.',
    'ph.transparency': 'Transparence',
    'ph.glass_hint': 'À quel point le verre diffuse ce qui est derrière lui.',
    'ph.action_button': 'Bouton Action',
    'ph.action_hint': 'Le bouton en haut à gauche ouvre cette application. Retouchez celle qui est choisie pour l’effacer.',
    'ph.recents': 'Récents', 'ph.voicemail': 'Messagerie', 'ph.keypad_tab': 'Clavier',
    'ph.no_recents_call': 'Aucun appel récent', 'ph.no_favourites': 'Aucun favori',
    'ph.no_contacts': 'Aucun contact', 'ph.no_photos': 'Aucune photo',
    'ph.no_places': 'Rien sur la carte pour le moment',
    'ph.mail_pick_sub': 'Choisissez votre adresse', 'ph.mail_create': 'Créer une adresse',
    'ph.mail_pick_hint': 'Cette adresse sera utilisée pour envoyer et recevoir vos e-mails.',
    'ph.vitality': 'Vitalité', 'ph.armour': 'Armure', 'ph.hunger': 'Faim',
    'ph.thirst': 'Soif', 'ph.stress': 'Stress', 'ph.all_well': 'Tout va bien',
    'ph.today': 'Aujourd’hui', 'ph.record': 'Dossier médical',
    'ph.los_santos': 'Los Santos', 'ph.weather_sun': 'Dégagé',
    'ph.month_jul': 'JUILLET', 'ph.in_game_date': 'Date en jeu',
    'ph.call': 'Appeler', 'ph.answer': 'Répondre', 'ph.hangup': 'Raccrocher',
    'ph.pass': 'Passer', 'ph.like': 'J’aime',
    'ph.recent': 'Récentes', 'ph.results': 'Résultats', 'ph.all_apps': 'Toutes les apps',
    'ph.switch_hint': 'Balayez une carte vers le haut pour la fermer',
    'ph.clear': 'Effacer', 'ph.close': 'Fermer', 'ph.done': 'OK', 'ph.delete': 'Supprimer',
    'ph.save': 'Enregistrer',
    'ph.airdrop': 'FruitDrop', 'ph.airdrop_share': 'Partager avec FruitDrop',
    'ph.airdrop_hint': 'Appareils iFruit à proximité avec le Bluetooth activé.',
    'ph.airdrop_scanning': 'Recherche des appareils…', 'ph.airdrop_none': 'Aucun appareil à proximité',
    'ph.airdrop_nearby': 'À proximité', 'ph.airdrop_sent': 'Envoyé',
    'ph.airdrop_incoming': 'FruitDrop entrant', 'ph.airdrop_from': 'De',
    'ph.airdrop_accept': 'Accepter', 'ph.airdrop_decline': 'Refuser',
    'ph.airdrop_saved': 'Enregistré', 'ph.airdrop_took': 'Accepté par',
    'ph.airdrop_declined': 'Refusé', 'ph.airdrop_bt': 'Activez le Bluetooth',
    'ph.airdrop_gone': 'Appareil indisponible', 'ph.airdrop_range': 'Trop loin',
    'ph.airdrop_busy': 'Trop de transferts en cours', 'ph.airdrop_x': 'Échec',
    'ph.copy': 'Copier', 'ph.forward': 'Transférer', 'ph.message_actions': 'Message',
    'ph.message_actions_hint': 'Maintenez un message ou glissez-le vers la droite pour afficher les actions.',
    'ph.copied': 'Copié', 'ph.write': 'Message', 'ph.attach': 'Pièce jointe',
    'ph.attach_photo': 'Photos récentes', 'ph.pick_photo': 'Choisir une photo',
    'ph.attach_url': 'Lien image ou GIF', 'ph.attach_send': 'Envoyer le média',
    'ph.attach_loc': 'Partager ma position', 'ph.msg_location': 'Position partagée',
    'ph.number': 'Numéro', 'ph.send': 'Envoyer', 'ph.forwarded': 'Message transféré',
    'ph.required_contact': 'Obligatoire',
    'ph.required_contact_hint': 'Contact ajouté par votre serveur',
    'ph.search_contacts': 'Rechercher un contact',
    'ph.share_my_number': 'Partager mon numéro',
    'ph.soc_join_sub': 'Créez votre compte', 'ph.soc_step': 'Étape',
    'ph.soc_number': 'Numéro de téléphone', 'ph.soc_sendcode': 'Envoyer le code',
    'ph.soc_number_hint': 'Un numéro est obligatoire. Un code de vérification vous sera envoyé par SMS.',
    'ph.c_note': 'Notes',
    'ph.message': 'Message',
    'ph.no_messages': 'Aucun message', 'ph.groups': 'Groupes', 'ph.unknown': 'Inconnu',
    'ph.emoji': 'Émojis', 'ph.emoji_hint': 'Touchez pour insérer', 'ph.emoji_recent': 'Récents',
    'ph.emoji_faces': 'Visages', 'ph.emoji_gestures': 'Gestes', 'ph.emoji_hearts': 'Cœurs',
    'ph.emoji_things': 'Objets', 'ph.emoji_recent_empty': 'Vos émojis récents apparaîtront ici',
    'ph.cc': 'Centre de contrôle', 'ph.notifs': 'Notifications', 'ph.notif_manage': 'Gérer',
    'ph.airplane': 'Mode avion', 'ph.cellular': 'Données cellulaires',
    'ph.wifi': 'Wi-Fi', 'ph.bluetooth': 'Bluetooth', 'ph.nowplaying': 'À l’écoute',
    'ph.brightness': 'Luminosité', 'ph.volume': 'Volume',
    'ph.vf_hint': 'Cadrez votre photo', 'ph.cam_photo': 'PHOTO',
    'ph.landscape': 'Paysage', 'ph.shooting': 'Prendre une photo',
    'ph.notif_done': 'OK', 'ph.clear_all': 'Tout effacer', 'ph.notif_empty': 'Aucune notification',
    'ph.nothing_playing': 'Rien en lecture', 'ph.focus': 'Concentration',
    'ph.store_search': 'Rechercher une application', 'ph.store_featured': 'À la une',
    'ph.store_editorial': 'Nos apps préférées pour Los Santos', 'ph.store_install': 'OBTENIR',
    'ph.store_open': 'Ouvrir', 'ph.store_delete': 'Retirer', 'ph.store_required': 'Intégrée',
    'ph.store_ratings': 'notes', 'ph.store_age': 'Âge', 'ph.store_size': 'Taille',
    'ph.store_previews': 'Aperçus', 'ph.store_preview_1': 'Une expérience claire et immédiate',
    'ph.store_preview_2': 'Tout ce qui compte, au premier regard',
    'ph.store_preview_3': 'Des contrôles conçus pour le tactile',
    'ph.about': 'À propos', 'ph.store_whats_new': 'Nouveautés',
    'ph.store_whats_new_body': 'Interface Clear Glass, gestes plus fluides et stabilité améliorée.',
    'ph.store_privacy': 'Confidentialité de l’app',
    'ph.store_privacy_body': 'Les données restent dans votre téléphone et votre serveur.',
    'ph.store_information': 'Informations', 'ph.store_dev': 'Développeur',
    'ph.store_cat': 'Catégorie', 'ph.store_version': 'Version',
    'ph.store_compatibility': 'Compatibilité', 'ph.store_phone_ready': 'Conçu pour iFruit',
    'ph.about_title': 'Informations', 'ph.about_device': 'Appareil',
    'ph.about_dev': 'Développé par', 'ph.about_foot': 'iFruit. Développé par vyrriox.',
    'ph.store_empty': 'Aucune application', 'ph.store_none': 'Aucun résultat', 'ph.all': 'Toutes',
    'ph.no_app': 'Aucune application', 'ph.loading': 'Chargement…',
    'ph.app_load_failed': 'Impossible de charger l’application',
    'ph.no_recents': 'Aucune app récente',
    'ph.torch': 'Lampe torche', 'ph.arrange_done': 'OK', 'app.camera': 'Appareil photo',
    'app.store': 'FruitStore', 'app.messages': 'Messages', 'app.phone': 'Téléphone',
    'app.contacts': 'Contacts', 'app.settings': 'Réglages', 'app.mail': 'Mail',
    'app.maps': 'Plans', 'app.music': 'Musique', 'app.health': 'Santé',
    'app.gallery': 'Photos', 'app.notes': 'Notes', 'app.bleeter': 'Bleeter',
    'app.snap': 'Snapmatic', 'app.hush': 'Hush', 'app.bank': 'Banque',
    'app.garage': 'Garage', 'app.property': 'Logement', 'app.wallet': 'Portefeuille',
    'app.jobs': 'Emplois', 'app.reminders': 'Rappels',
    'app.calc': 'Calculatrice', 'app.mdt': 'MDT',
    'ph.cat_essentials': 'Essentiels', 'ph.cat_utilities': 'Utilitaires',
    'ph.cat_social': 'Réseaux sociaux', 'ph.cat_finance': 'Finance',
    'ph.cat_entertainment': 'Divertissement', 'ph.cat_health': 'Santé',
    'ph.cat_travel': 'Voyage', 'ph.cat_work': 'Travail',
    'ph.desc_store': 'Découvrez, installez et gérez les applications disponibles sur votre serveur.',
    'ph.desc_messages': 'Conversations, groupes, photos, localisation et réactions.',
    'ph.desc_music': 'Votre bibliothèque et les sources audio autour de vous.',
    'ph.library': 'Bibliothèque', 'ph.library_empty': 'Aucun titre',
    'ph.library_hint': 'Ajoutez vos titres pour construire votre bibliothèque iFruit.',
    'ph.track_add': 'Ajouter un titre', 'ph.track_edit': 'Modifier le titre',
    'ph.track_title': 'Titre', 'ph.track_artist': 'Artiste', 'ph.track_album': 'Album',
    'ph.track_url': 'Lien audio', 'ph.track_art': 'Lien de la pochette (facultatif)',
    'ph.track_hint': 'Les hébergeurs audio autorisés sont définis par votre serveur.',
    'ph.track_nourl': 'Ajoutez un lien', 'ph.new_track': 'Nouveau titre',
    'ph.unknown_artist': 'Artiste inconnu', 'ph.single': 'Single',
    'ph.untitled': 'Sans titre', 'ph.playing': 'En lecture', 'ph.paused': 'En pause',
    'ph.pause': 'Mettre en pause', 'ph.resume': 'Reprendre', 'ph.stop': 'Arrêter',
    'ph.playing_ear': 'Lecture dans vos écouteurs', 'ph.play': 'Lire',
    'ph.music_home': 'Accueil', 'ph.music_new': 'Nouveautés', 'ph.music_radio': 'Radio',
    'ph.music_welcome': 'Bienvenue dans Music', 'ph.music_yours': 'Toute votre musique',
    'ph.music_welcome_hint': 'Ajoutez vos titres, créez votre file et choisissez où les écouter.',
    'ph.music_top_pick': 'À écouter maintenant', 'ph.music_featured': 'Sélection iFruit',
    'ph.music_featured_hint': 'Une sélection inspirée des nuits, des routes et des quartiers de Los Santos.',
    'ph.los_santos_sound': 'Le son de Los Santos', 'ph.music_radio_title': 'Radio iFruit',
    'ph.music_radio_hint': 'Les sources audio que vous pouvez réellement contrôler autour de vous.',
    'ph.music_air_hint': 'Une source apparaîtra ici dès qu’un son sera à votre portée.',
    'ph.music_search_hint': 'Recherchez dans votre musique',
    'ph.music_search_everything': 'Titres, artistes, albums et sources à proximité.',
    'ph.music_search_placeholder': 'Artistes, titres, albums',
    'ph.music_try_search': 'Essayez un autre titre, artiste ou album.',
    'ph.music_synced': 'Lecture synchronisée', 'ph.music_metadata': 'Informations du titre',
    'ph.music_live_source': 'Source en direct', 'ph.music_device': 'Appareil audio',
    'ph.music_headphones': 'Écouteurs', 'ph.music_phone': 'Haut-parleur iFruit',
    'ph.music_vehicle': 'Autoradio', 'ph.music_jukebox': 'Juke-box',
    'ph.music_boombox': 'Enceinte', 'ph.recently_played': 'Écoutés récemment',
    'ph.made_for_you': 'Rien que pour vous', 'ph.personal_mix': 'Mix personnel',
    'ph.favorites_mix': 'Vos favoris', 'ph.favorites_mix_hint': 'Vos coups de cœur réunis dans une file.',
    'ph.new_releases': 'Nouveautés', 'ph.albums': 'Albums', 'ph.songs': 'Morceaux',
    'ph.browse_categories': 'Explorer par catégorie', 'ph.genre_urban': 'Urbain',
    'ph.genre_electronic': 'Électronique', 'ph.genre_rock': 'Rock', 'ph.genre_chill': 'Détente',
    'ph.on_air': 'En direct autour de vous', 'ph.start_station': 'Lancer une station',
    'ph.artist_station': 'Station de l’artiste', 'ph.live': 'Direct',
    'ph.previous': 'Précédent', 'ph.next': 'Suivant', 'ph.more': 'Plus d’options',
    'ph.add': 'Ajouter', 'ph.see_all': 'Tout afficher', 'ph.favorite': 'Favori',
    'ph.favorited': 'Dans les favoris', 'ph.favourites': 'Favoris',
    'ph.music_favorited': 'Ajouté aux favoris', 'ph.music_unfavorited': 'Retiré des favoris',
    'ph.no_favorites': 'Aucun favori pour le moment', 'ph.add_queue': 'Ajouter à la file',
    'ph.added_queue': 'Ajouté à la file', 'ph.queue': 'File', 'ph.up_next': 'À suivre',
    'ph.queue_empty': 'La file est vide', 'ph.clear_queue': 'Vider la file',
    'ph.choose_output': 'Choisir la sortie audio', 'ph.output': 'Sortie audio',
    'ph.output_private': 'Écoute privée, pour vous uniquement',
    'ph.output_nearby': 'Audible par les personnes proches',
    'ph.output_vehicle': 'Diffuse dans le véhicule si vous avez les clés',
    'ph.no_results': 'Aucun résultat', 'ph.no_music': 'Aucune source à portée',
    'ph.desc_health': 'Votre activité, vos informations médicales et vos tendances.',
    'ph.desc_generic': 'Une application conçue pour iFruit et son interface Clear Glass.',
    'app.cipher': 'Cipher',
    'app.example': 'AppKit Lab',
    'ph.desc_cipher': 'Messagerie privée chiffrée de bout en bout, protégée par une identité anonyme.',
    'ph.cipher_private_network': 'Réseau privé iFruit',
    'ph.cipher_welcome': 'Disparaissez du réseau public',
    'ph.cipher_welcome_hint': 'Créez une identité anonyme. Votre clé privée reste sur cet appareil.',
    'ph.cipher_e2e': 'Chiffrement de bout en bout',
    'ph.cipher_e2e_hint': 'Clés ECDH P-256 et messages AES-256-GCM',
    'ph.cipher_server_blind': 'Le serveur ne peut pas lire vos messages',
    'ph.cipher_handle': 'Identifiant privé (@)',
    'ph.cipher_codename': 'Nom de code',
    'ph.cipher_pin': 'Code Cipher à 6 chiffres',
    'ph.cipher_pin_confirm': 'Confirmer le code',
    'ph.cipher_create': 'Créer mon identité',
    'ph.cipher_pin_hint': 'Ce code chiffre votre clé privée locale.',
    'ph.cipher_pin_mismatch': 'Les deux codes ne correspondent pas',
    'ph.cipher_generating': 'Génération des clés…',
    'ph.cipher_identity_ready': 'Identité chiffrée créée',
    'ph.cipher_locked': 'Coffre verrouillé',
    'ph.cipher_unlock_hint': 'Saisissez votre code pour déchiffrer la clé privée.',
    'ph.cipher_key_missing': 'La clé privée est absente de cet appareil.',
    'ph.cipher_unlock': 'Déverrouiller Cipher',
    'ph.cipher_recover': 'Remplacer la clé privée',
    'ph.cipher_recover_hint': "Une nouvelle clé supprimera l'ancien historique.",
    'ph.cipher_recover_title': 'Récupération',
    'ph.cipher_new_key': 'Créer une nouvelle clé',
    'ph.cipher_new_key_hint': 'Cette action détruit les anciennes conversations.',
    'ph.cipher_replace_key': 'Détruire et remplacer la clé',
    'ph.cipher_key_replaced': 'Nouvelle clé activée',
    'ph.cipher_network_live': 'Circuit sécurisé actif',
    'ph.cipher_security': 'Identité et sécurité',
    'ph.cipher_active': 'Actif',
    'ph.cipher_chats': 'Canaux privés',
    'ph.cipher_no_chats': 'Aucun canal ouvert',
    'ph.cipher_no_chats_hint': 'Trouvez un identifiant Cipher pour établir une session.',
    'ph.cipher_start': 'Ouvrir un canal',
    'ph.cipher_new_chat': 'Nouveau canal',
    'ph.cipher_find_handle': 'Rechercher @identifiant',
    'ph.cipher_find_hint': 'Saisissez au moins deux caractères.',
    'ph.cipher_no_user': 'Aucune identité Cipher trouvée',
    'ph.cipher_unreadable': 'Message impossible à déchiffrer',
    'ph.cipher_secure_session': 'Session sécurisée',
    'ph.cipher_secure_session_hint': 'Seuls les deux appareils possèdent la clé.',
    'ph.cipher_first_message': 'La session est prête. Envoyez le premier paquet.',
    'ph.cipher_write': 'Message chiffré',
    'ph.cipher_burn_off': 'Conserver',
    'ph.cipher_burn_5m': '5 min',
    'ph.cipher_burn_1h': '1 heure',
    'ph.cipher_burn_1d': '24 heures',
    'ph.cipher_disappearing': 'Messages éphémères',
    'ph.cipher_burn_hint': 'Le message disparaît automatiquement.',
    'ph.cipher_burn_keep': "Les messages restent jusqu'à l'effacement.",
    'ph.cipher_verify': 'Vérifier la session',
    'ph.cipher_verified': 'Session chiffrée vérifiée',
    'ph.cipher_safety_number': 'Empreinte de sécurité',
    'ph.cipher_verify_hint': 'Comparez cette empreinte en personne.',
    'ph.cipher_clear_chat': 'Effacer ce canal pour moi',
    'ph.cipher_cleared': 'Canal effacé',
    'ph.cipher_message_info': 'Détails du paquet',
    'ph.cipher_encrypted': 'Paquet chiffré',
    'ph.cipher_encrypted_hint': "Le contenu a été chiffré avant l'envoi.",
    'ph.cipher_recipient': 'Destinataire',
    'ph.cipher_delivery': 'État',
    'ph.cipher_delivered': 'Remis au relais',
    'ph.cipher_your_fingerprint': 'Votre empreinte publique',
    'ph.cipher_lock_now': 'Verrouiller maintenant',
    'ph.cipher_lock_now_hint': 'Retirer la clé de la mémoire',
    'ph.cipher_destroy': "Détruire l'identité",
    'ph.cipher_destroy_hint': 'Supprimer la clé, le profil et les conversations',
    'ph.cipher_destroy_confirm': 'Aucune récupération possible',
    'ph.cipher_destroy_confirm_hint': 'Saisissez votre code Cipher.',
    'ph.cipher_destroy_action': 'Détruire définitivement',
    'ph.cipher_packet': 'Nouveau paquet chiffré',
    'ph.cipher_err_badpin': 'Code Cipher incorrect',
    'ph.cipher_err_handle': 'Identifiant invalide',
    'ph.cipher_err_pin': 'Le code doit contenir 6 chiffres',
    'ph.cipher_err_fields': 'Complétez tous les champs',
    'ph.cipher_err_crypto': 'Le chiffrement a échoué',
    'ph.cipher_err_storage': "Impossible d'enregistrer la clé",
    'ph.cipher_err_nouser': 'Identité Cipher introuvable',
    'ph.app_actions': 'Actions de l’app',
    'ph.app_actions_hint': 'Raccourcis disponibles dans toutes les applications iFruit.',
    'ph.search_in_app': 'Rechercher dans l’app',
    'ph.refresh_app': 'Actualiser',
    'ph.set_action_app': 'Utiliser avec le bouton Action',
    'ph.selected': 'Sélectionnée',
    'ph.enable_notifications': 'Réactiver les notifications',
    'ph.mute_notifications': 'Masquer les notifications',
    'ph.notifications_enabled': 'Notifications réactivées',
    'ph.notifications_muted': 'Notifications masquées',
    'ph.view_in_store': 'Voir dans le FruitStore',
    'ph.action_app_saved': 'Bouton Action configuré',
    'ph.pick_contact': 'Choisir un contact',
    'ph.photo': 'Photo',
    'ph.confirm': 'Confirmer',
    'ph.share': 'Partager',
    'ph.share_messages': 'Partager par Messages',
    'ph.store_features': 'Fonctionnalités',
    'ph.store_permissions': 'Accès demandés',
    'ph.permission_storage': 'Stockage de l’app',
    'ph.permission_contacts': 'Contacts',
    'ph.permission_photos': 'Photos',
    'ph.permission_location': 'Position',
    'ph.permission_notifications': 'Notifications',
    'ph.permission_messages': 'Messages',
    'ph.permission_calls': 'Appels',
    'ph.permission_apps': 'Ouvrir des apps',
    'ph.permission_sharing': 'Partage'
  };
  var previewParams = new URLSearchParams(window.location.search);
  var cipherPreview = previewParams.has('cipher');
  var allPreview = previewParams.has('all');
  var available = [
    ['phone', 'app.phone', 'phone', true, 'essentials'],
    ['messages', 'app.messages', 'messages', true, 'essentials'],
    ['contacts', 'app.contacts', 'contacts', true, 'essentials'],
    ['store', 'app.store', 'store', true, 'essentials'],
    ['settings', 'app.settings', 'settings', true, 'utilities'],
    ['camera', 'app.camera', 'camera', false, 'utilities'],
    ['gallery', 'app.gallery', 'images', false, 'utilities'],
    ['mail', 'app.mail', 'mail', false, 'work'],
    ['maps', 'app.maps', 'map', false, 'travel'],
    ['music', 'app.music', 'music', false, 'entertainment'],
    ['health', 'app.health', 'heart', false, 'health'],
    ['notes', 'app.notes', 'note', false, 'utilities'],
    ['bleeter', 'app.bleeter', 'bleet', false, 'social'],
    ['snap', 'app.snap', 'snap', false, 'social'],
    ['hush', 'app.hush', 'hush', false, 'social'],
    ['cipher', 'app.cipher', 'cipher', false, 'social'],
    ['bank', 'app.bank', 'bank', false, 'finance'],
    ['garage', 'app.garage', 'garage', false, 'utilities'],
    ['property', 'app.property', 'house', false, 'utilities'],
    ['wallet', 'app.wallet', 'wallet', false, 'finance'],
    ['jobs', 'app.jobs', 'jobs', false, 'work'],
    ['reminders', 'app.reminders', 'check', false, 'utilities'],
    ['calc', 'app.calc', 'calc', false, 'utilities'],
    ['mdt', 'app.mdt', 'shield', false, 'work'],
    ['example', 'app.example', 'note', false, 'utilities']
  ].map(function (item, index) {
    return {
      id: item[0], label: item[1], icon: item[2], required: item[3],
      optional: !item[3], category: item[4], slot: index + 1,
      dock: ['phone', 'messages', 'contacts', 'settings'].indexOf(item[0]) !== -1,
      owner: 'v-phone',
      developer: 'iFruit Studio',
      version: '2.0.0',
      permissions: item[0] === 'camera' ? ['photos'] :
        (item[0] === 'messages' ? ['contacts', 'photos', 'location', 'notifications'] : []),
      features: item[0] === 'example'
        ? ['Stockage persistant', 'Sélecteurs natifs', 'Cycle de vie', 'Navigation inter-apps']
        : ['Gestes tactiles', 'Clear Glass', 'Synchronisation en direct'],
      keywords: [item[0], item[4], 'iFruit']
    };
  });
  var sdkExample = available.find(function (app) { return app.id === 'example'; });
  if (sdkExample) {
    sdkExample.page = '../apps/example/index.html';
    sdkExample.developer = 'iFruit SDK';
    sdkExample.permissions = ['storage', 'contacts', 'photos', 'location', 'notifications', 'apps', 'sharing'];
  }
  var installed = available.filter(function (app) {
    return allPreview ||
      ['phone', 'messages', 'contacts', 'store', 'settings', 'camera', 'mail', 'maps', 'music', 'health', 'gallery'].indexOf(app.id) !== -1 ||
      (cipherPreview && app.id === 'cipher') || (previewParams.has('sdk') && app.id === 'example');
  });
  var contacts = [
    { id: 'required:1', name: 'Urgences', number: '911', favourite: 1, system: true, required: true,
      note: 'Contact obligatoire défini dans config.lua' },
    { id: 1, name: 'Maya', number: '555-0108' },
    { id: 2, name: 'Alex', number: '555-0142' },
    { id: 3, name: 'Los Santos Customs', number: '555-0199' }
  ];
  var conversations = [
    { number: '555-0108', body: 'On se retrouve au garage dans cinq minutes.', unread: 2 },
    { number: '555-0142', body: 'Le nouveau téléphone est incroyable ✨', unread: 0 }
  ];
  var demoThreads = {
    '555-0108': [
      { mine: false, body: 'Tu as vu la nouvelle interface ?', kind: 'text' },
      { mine: true, body: 'Oui, le Clear Glass est beaucoup plus fluide.', kind: 'text' },
      { mine: false, body: 'On se retrouve au garage dans cinq minutes.', kind: 'text' },
      { mine: true, body: '', kind: 'location', attachment: '215.4;-810.2' }
    ],
    '555-0142': [
      { mine: false, body: 'Le nouveau téléphone est incroyable ✨', kind: 'text' },
      { mine: true, body: 'Teste un appui long sur ce message.', kind: 'text' }
    ]
  };
  var cipherMe = {
    handle: 'nightowl',
    displayName: 'Night Owl',
    publicKey: '{"kty":"EC","crv":"P-256","x":"preview","y":"preview"}',
    fingerprint: '9A:31:7F:C2:08:EE:64:BD:11:57:42:AC:73:0D:91:5E'
  };
  var cipherPeers = {
    raven: {
      handle: 'raven', displayName: 'Raven',
      publicKey: '{"kty":"EC","crv":"P-256","x":"preview","y":"preview"}',
      fingerprint: '71:2B:DC:90:44:18:AF:2E:9D:05:C1:77:63:BE:42:10'
    },
    zero_trace: {
      handle: 'zero_trace', displayName: 'Zero Trace',
      publicKey: '{"kty":"EC","crv":"P-256","x":"preview","y":"preview"}',
      fingerprint: '2C:83:16:EA:50:B4:9A:33:7D:02:E8:61:F9:45:AC:70'
    }
  };
  var cipherMessages = {
    raven: [
      { id: 1, mine: false, envelope: JSON.stringify({ v: 1, iv: 'demo', data: 'demo', plain: 'Le colis est prêt. Même point que la dernière fois.' }), burn: 0, at: '2026-07-23 21:32:00' },
      { id: 2, mine: true, envelope: JSON.stringify({ v: 1, iv: 'demo', data: 'demo', plain: 'Reçu. J’efface le canal après la remise.' }), burn: 3600, at: '2026-07-23 21:34:00' }
    ],
    zero_trace: [
      { id: 3, mine: false, envelope: JSON.stringify({ v: 1, iv: 'demo', data: 'demo', plain: 'Nouvelle fréquence disponible.' }), burn: 86400, at: '2026-07-23 19:08:00' }
    ]
  };
  var cipherExists = !previewParams.has('cipher-new');
  var setupPreview = previewParams.has('setup');
  var previewPasscode = '258000';
  var prefs = {
    setupComplete: !setupPreview,
    setupVersion: setupPreview ? 1 : 2, ownerName: 'Leo', deviceName: 'iFruit de Leo',
    securityEnabled: !setupPreview, faceId: !setupPreview,
    wallpaper: 'ifruit', glass: 28, brightness: .92,
    wifi: true, cellular: true, bluetooth: true
  };
  var previewMusicLibrary = [
    { title: 'Midnight Drive', artist: 'Neon Palms', album: 'Vinewood After Dark', url: 'https://youtu.be/preview-midnight', favorite: true },
    { title: 'Pacific Blue', artist: 'Maya Sol', album: 'Coastline', url: 'https://youtu.be/preview-pacific', favorite: true },
    { title: 'No Signal', artist: 'Zero Trace', album: 'Underground', url: 'https://youtu.be/preview-signal' },
    { title: 'Downtown Heat', artist: 'Kilo Avenue', album: 'Los Santos Nights', url: 'https://youtu.be/preview-heat', favorite: true },
    { title: 'Mirrorball', artist: 'The Del Perro Club', album: 'Mirrorball', url: 'https://youtu.be/preview-mirror' },
    { title: 'Sunset Boulevard', artist: 'Neon Palms', album: 'Vinewood After Dark', url: 'https://youtu.be/preview-sunset' },
    { title: 'After Hours', artist: 'Maya Sol', album: 'Coastline', url: 'https://youtu.be/preview-hours' },
    { title: 'Northbound', artist: 'Kilo Avenue', album: 'Los Santos Nights', url: 'https://youtu.be/preview-north' }
  ];
  var previewMusicStorage = {
    library_manifest: JSON.stringify({ v: 2, chunks: 1 }),
    library_0: JSON.stringify(previewMusicLibrary),
    recent: JSON.stringify([
      'https://youtu.be/preview-midnight',
      'https://youtu.be/preview-pacific',
      'https://youtu.be/preview-signal'
    ])
  };
  var previewSdkStorage = {};
  var previewMusicSources = [{
    id: 'preview-radio', title: 'Midnight Drive', artist: 'Neon Palms',
    album: 'Vinewood After Dark', url: 'https://youtu.be/preview-midnight',
    kind: 'jukebox', volume: .55, paused: false
  }];
  window.__VPHONE_PREVIEW_POST__ = function (name, payload) {
    if (name === 'ambient') {
      return { ok: true, weather: 'CLEAR', hours: 18, minutes: 27, day: 23, month: 7 };
    }
    if (name === 'conversation') {
      return { ok: true, messages: demoThreads[String(payload.number)] || demoThreads['555-0108'] };
    }
    if (name === 'cipher') {
      if (payload.op === 'me') {
        return { ok: true, exists: cipherExists, unlocked: true, profile: cipherExists ? cipherMe : null, demo: true };
      }
      if (payload.op === 'list') {
        return {
          ok: true, unread: 1,
          conversations: Object.keys(cipherMessages).filter(function (handle) {
            return cipherMessages[handle].length > 0;
          }).map(function (handle, index) {
            var messages = cipherMessages[handle];
            var last = messages[messages.length - 1];
            return {
              peer: cipherPeers[handle], envelope: last.envelope, burn: last.burn,
              at: last.at, unread: index === 0 ? 1 : 0
            };
          })
        };
      }
      if (payload.op === 'thread') {
        return {
          ok: true, peer: cipherPeers[payload.handle] || cipherPeers.raven,
          messages: cipherMessages[payload.handle] || [], unread: 0
        };
      }
      if (payload.op === 'lookup') {
        var query = String(payload.query || '').toLowerCase();
        return {
          ok: true,
          results: Object.keys(cipherPeers).map(function (key) { return cipherPeers[key]; })
            .filter(function (peer) { return peer.handle.indexOf(query) === 0; })
        };
      }
      if (payload.op === 'send') {
        var handle = payload.handle || 'raven';
        var row = {
          id: Date.now(), mine: true, envelope: payload.envelope, burn: Number(payload.burn || 0),
          at: new Date().toISOString().slice(0, 19).replace('T', ' '), peer: cipherPeers[handle]
        };
        if (!cipherMessages[handle]) cipherMessages[handle] = [];
        cipherMessages[handle].push(row);
        return { ok: true, message: row };
      }
      if (payload.op === 'profile') {
        cipherMe.displayName = payload.displayName || cipherMe.displayName;
        return { ok: true, profile: cipherMe, demo: true };
      }
      if (payload.op === 'unlock' || payload.op === 'rotate') {
        return { ok: true, profile: cipherMe, demo: true };
      }
      if (payload.op === 'clear') {
        cipherMessages[payload.handle] = [];
        return { ok: true };
      }
      if (payload.op === 'destroy') {
        cipherExists = false;
        return { ok: true };
      }
      if (payload.op === 'create') {
        cipherExists = true;
        cipherMe.handle = payload.handle;
        cipherMe.displayName = payload.displayName;
        return { ok: true, profile: cipherMe, demo: true };
      }
      return { ok: true, profile: cipherMe };
    }
    if (name === 'photos') return { ok: true, photos: [] };
    if (name === 'appStorage') {
      if (payload.op === 'get') return { ok: true, value: previewMusicStorage[payload.key] || '' };
      if (payload.op === 'set') previewMusicStorage[payload.key] = String(payload.value || '');
      return { ok: true };
    }
    if (name === 'sdkStorage') {
      if (payload.op === 'get') return { ok: true, value: previewSdkStorage[payload.key] || '' };
      if (payload.op === 'all') return { ok: true, values: Object.assign({}, previewSdkStorage) };
      if (payload.op === 'clear') previewSdkStorage = {};
      else if (payload.op === 'remove') delete previewSdkStorage[payload.key];
      else if (payload.op === 'set') {
        previewSdkStorage[payload.key] = typeof payload.value === 'string'
          ? payload.value : JSON.stringify(payload.value);
      }
      return { ok: true };
    }
    if (name === 'sdkLocation') {
      return { ok: true, x: 215.4, y: -810.2, z: 30.7, heading: 180 };
    }
    if (name === 'app' && payload.app === 'music') {
      return { ok: true, enabled: true, sources: previewMusicSources.slice() };
    }
    if (name === 'music') {
      if (payload.action === 'play') {
        var source = {
          id: 'preview-now', title: payload.title || 'Sans titre', url: payload.url || '',
          kind: payload.kind || 'headphones', volume: Number(payload.volume || .65), paused: false
        };
        previewMusicSources = previewMusicSources.filter(function (row) { return row.id !== source.id; });
        previewMusicSources.unshift(source);
        return { ok: true, id: source.id };
      }
      var controlled = previewMusicSources.find(function (row) { return row.id === payload.id; });
      if (!controlled) return { error: 'nosource' };
      if (payload.action === 'stop') {
        previewMusicSources = previewMusicSources.filter(function (row) { return row.id !== payload.id; });
      } else if (payload.action === 'pause') controlled.paused = true;
      else if (payload.action === 'resume') controlled.paused = false;
      else if (payload.action === 'volume') controlled.volume = Number(payload.volume);
      return { ok: true };
    }
    if (name === 'health') {
      return { ok: true, steps: 6842, distance: 4.7, calories: 418, heart: 74, sleep: 7.4 };
    }
    if (name === 'send') {
      return {
        ok: true, body: payload.body || '', kind: payload.kind || 'text',
        attachment: payload.attachment || ''
      };
    }
    if (name === 'sendloc') return { ok: true, attachment: '215.4;-810.2' };
    if (name === 'install') {
      var target = available.find(function (app) { return app.id === payload.app; });
      installed = installed.filter(function (app) { return app.id !== payload.app; });
      if (payload.install && target) installed.push(target);
      return { ok: true };
    }
    if (name === 'refresh') {
      return {
        ok: true, apps: installed, available: available, contacts: contacts,
        conversations: conversations, cipherUnread: 1, prefs: prefs
      };
    }
    if (name === 'prefs') {
      var nextPrefs = Object.assign({}, payload);
      if (nextPrefs.passcode) {
        previewPasscode = String(nextPrefs.passcode);
        nextPrefs.securityEnabled = true;
        delete nextPrefs.passcode;
      }
      Object.assign(prefs, nextPrefs);
      return { ok: true, prefs: prefs };
    }
    if (name === 'unlock') {
      if (payload && payload.faceId && prefs.faceId) return { ok: true, method: 'faceId' };
      return String(payload && payload.passcode || '') === previewPasscode
        ? { ok: true, method: 'passcode' }
        : { error: 'badcode', attemptsRemaining: 4 };
    }
    return { ok: true };
  };
  window.dispatchEvent(new MessageEvent('message', {
    source: window,
    data: {
      action: 'open', locale: 'fr-FR', strings: strings, playerName: 'Leo', number: '555-0127',
      apps: installed, available: available, contacts: contacts, conversations: conversations,
      photos: [], camera: true, vmUnread: 2, cipherUnread: 1,
      prefs: prefs,
      wallpapers: ['ifruit', 'aurora', 'lagoon'], power: { battery: 82, signal: 4, charging: false },
      theme: { auto: true }, sounds: { ringtones: ['classic'], alerts: ['ping'] }
    }
  }));
  setTimeout(function () {
    window.dispatchEvent(new MessageEvent('message', {
      source: window,
      data: {
        action: 'banner', banner: {
          app: 'messages', icon: 'messages', title: 'Maya',
          body: 'On se retrouve au garage dans cinq minutes.'
        }
      }
    }));
  }, 350);
}());
