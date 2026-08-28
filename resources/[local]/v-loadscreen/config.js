/**
 * v-loadscreen - configuration
 * author: doc, vyrriox
 *
 * EN | This single file drives the whole loading screen: identity, colours,
 *      backgrounds, music, tips, keybinds, links and shutdown behaviour.
 *      Restart the resource after editing (`restart v-loadscreen`).
 * FR | Ce fichier unique pilote tout l'ecran de chargement : identite, couleurs,
 *      fonds, musique, astuces, raccourcis, liens et fermeture.
 *      Redemarre la ressource apres modification (`restart v-loadscreen`).
 *
 * Paths are relative to the resource root, e.g. 'assets/backgrounds/aurora.webm'.
 */
window.DocLoadingConfig = {
  /* ------------------------------------------------------------------ */
  /* 1. Language                                                         */
  /* ------------------------------------------------------------------ */
  // 'fr' or 'en'. Every string shown on screen lives in `locales` at the bottom.
  locale: 'fr',

  /* ------------------------------------------------------------------ */
  /* 2. Identity                                                         */
  /* ------------------------------------------------------------------ */
  identity: {
    // Logo shown in the middle. Any web format (webp / png / svg / gif).
    // Set to null to hide it and show the animated text title instead.
    logo: 'assets/logo.webp',
    logoMaxWidth: 32, // percentage of the screen width, 10 to 70

    // Server name. Always used by the pill in the top left corner.
    name: 'Your Server Name',
    // Also print the name under the logo, animated letter by letter. Off by
    // default because the shipped logo already spells it out; turn it on if
    // your logo is a symbol rather than a wordmark.
    showTitle: false,

    // One line under the logo. Leave empty to hide it.
    tagline: 'Serveur serious RP francophone',

    // Small pill in the top left corner.
    showServerPill: true,
    // Live player count, read from the server.
    showPlayerCount: true,
  },

  /* ------------------------------------------------------------------ */
  /* 3. Theme - warm Vice City by default                                */
  /* ------------------------------------------------------------------ */
  theme: {
    cyan: '#17e8ff',
    teal: '#00d9b2',
    violet: '#a855f7',
    magenta: '#ff2d95',
    pink: '#ff5fa2',
    coral: '#ff6b4a',
    orange: '#ff9f2e',
    gold: '#ffd166',

    ink: '#170424',        // deepest background colour
    text: '#fff2ea',       // main text
    textMuted: '#d7a6c6',  // secondary text

    // Glass panels.
    panelOpacity: 0.30,    // 0 (invisible) to 1 (solid)
    // Blur costs GPU time in proportion to its radius, and the backdrop behind
    // the panels is a moving video, so it is recomputed every frame. 18 looks
    // the same as 30 through a 30 % panel and costs noticeably less.
    panelBlur: 18,         // pixels
    cornerRadius: 18,      // pixels

    // Accent gradient used by the progress bar, borders, titles and glows.
    // Two to six colours; it is rebuilt automatically everywhere.
    gradient: ['#17e8ff', '#a855f7', '#ff2d95', '#ff9f2e'],
  },

  /* ------------------------------------------------------------------ */
  /* 4. Background                                                       */
  /* ------------------------------------------------------------------ */
  background: {
    // 'slideshow' cycles through `sources`, 'single' always shows the first one.
    mode: 'slideshow',
    // Seconds each source stays on screen. Videos shorter than this loop.
    interval: 20,
    // Crossfade duration in seconds.
    fade: 1.8,
    // Slow zoom and pan on top of each source. false keeps a static frame.
    kenBurns: true,
    // Random order.
    shuffle: false,

    // type: 'video' | 'image' | 'generated'
    //   video     -> src (webm / mp4), `poster` shows while it buffers
    //   image     -> src (webp / jpg / png)
    //   generated -> painted live in the browser, weighs nothing and stays
    //                sharp at any resolution
    //
    // `focus` is the part of the picture to keep when the screen is a
    // different shape from the source (any CSS object-position value).
    // Everything is cropped with `cover`, so 16:9, 21:9, 4:3 and vertical
    // screens all get a full-bleed image with no bars and no distortion.
    sources: [
      { type: 'video', src: 'assets/backgrounds/synthwave.webm', poster: 'assets/backgrounds/synthwave.webp' },
      { type: 'image', src: 'assets/backgrounds/server-1.webp', focus: '50% 45%' },
      { type: 'image', src: 'assets/backgrounds/server-3.webp', focus: '55% 55%' },
      { type: 'image', src: 'assets/backgrounds/server-2.webp', focus: '50% 55%' },
      { type: 'image', src: 'assets/backgrounds/server-4.webp', focus: '50% 50%' },
      { type: 'image', src: 'assets/backgrounds/server-5.webp', focus: '55% 50%' },
      // Also shipped, uncomment to add it to the rotation:
      // { type: 'video', src: 'assets/backgrounds/aurora.webm', poster: 'assets/backgrounds/aurora.webp' },
      // Painted live in the browser, costs nothing to download:
      // { type: 'generated' },
    ],

    // Dark wash painted over the background so text stays readable.
    // 0 = raw background, 1 = almost black.
    scrim: 0.5,
    // Extra colour wash in the theme tint.
    tint: 0.24,
  },

  /* ------------------------------------------------------------------ */
  /* 5. Effects                                                          */
  /* ------------------------------------------------------------------ */
  effects: {
    particles: true,       // embers drifting up, plus the odd shooting streak
    particleDensity: 1.0,  // 0.2 (sparse) to 2.0 (busy)
    aurora: true,          // slow colour blobs behind the panels
    grain: true,           // film grain
    scanlines: false,      // CRT lines, off by default
    vignette: true,
    parallax: true,        // layers react to the mouse
    cursorGlow: true,
    intro: true,           // curtain animation when the screen appears
    frame: true,           // neon corner brackets
    beam: true,            // light beam sweeping across now and then
    glitch: true,          // chromatic flash when the background changes

    // Turns every heavy effect off at once. Use it if a player reports a slow
    // first load. Players can also toggle it themselves from the settings panel.
    performanceMode: false,
  },

  /* ------------------------------------------------------------------ */
  /* 6. Music                                                            */
  /* ------------------------------------------------------------------ */
  music: {
    enabled: true,
    volume: 0.35,     // starting volume, 0 to 1
    fadeIn: 3.0,      // seconds
    shuffle: true,
    loop: true,

    // Player widget in the top right corner: play / pause, previous, next,
    // volume slider, mute, and a live spectrum.
    showPlayer: true,
    // Start the widget open instead of collapsed to a single button.
    playerExpanded: true,
    // Remember volume, mute and the settings toggles between sessions.
    rememberChoice: true,

    // Prints a few lines per track to the client console (F8): what was loaded,
    // whether it started, and the state of the audio element three seconds
    // later. Turn it on if a player reports silence, and off again afterwards.
    // A real failure is reported either way, once, without this.
    debug: false,

    // Local files or full https:// URLs. Add or remove lines freely; with
    // `shuffle` on, the order is drawn again on every connection, so a player
    // rarely hears the same opening twice.
    //
    // Deleting a line here does not stop the file being downloaded: to actually
    // trim the resource, delete the .mp3 from assets/music/ as well.
    tracks: [
      { title: 'Neon Horizon', artist: 'doc-loading', src: 'assets/music/neon-horizon.mp3' },
      { title: 'Sunset Boulevard', artist: 'doc-loading', src: 'assets/music/sunset-boulevard.mp3' },
      { title: 'Ocean Drive', artist: 'doc-loading', src: 'assets/music/ocean-drive.mp3' },
      { title: 'Midnight Palms', artist: 'doc-loading', src: 'assets/music/midnight-palms.mp3' },
      { title: 'Vice Nights', artist: 'doc-loading', src: 'assets/music/vice-nights.mp3' },
      { title: 'Afterglow', artist: 'doc-loading', src: 'assets/music/afterglow.mp3' },
      // { title: 'My track', artist: 'Someone', src: 'assets/music/my-track.mp3' },
    ],
  },

  /* ------------------------------------------------------------------ */
  /* 7. Settings panel offered to the player                             */
  /* ------------------------------------------------------------------ */
  settings: {
    enabled: true,
    allowMusic: true,       // mute / volume / skip track
    allowBackground: true,  // pause the slideshow, skip to the next background
    allowEffects: true,     // particles, grain, scanlines, performance mode
  },

  /* ------------------------------------------------------------------ */
  /* 8. Tips                                                             */
  /* ------------------------------------------------------------------ */
  tips: {
    enabled: true,
    interval: 9,   // seconds per tip
    shuffle: true,
    // Tip texts live in `locales` below so they follow the chosen language.
  },

  /* ------------------------------------------------------------------ */
  /* 9. Keybinds strip                                                   */
  /* ------------------------------------------------------------------ */
  keybinds: {
    enabled: true,
    // `label` points at an entry in locales.<lang>.keybinds so the wording
    // follows the chosen language. Emotes live in the radial menu and the radio
    // is handled from the inventory, so neither needs its own key here.
    // The framework's own default bindings (RegisterKeyMapping); a player who rebinds one in
    // the game settings sees their own key, this shows the default. Phone is F1, the target
    // eye is Left Alt, engine is K and the seat swap is G - not the qb defaults this shipped
    // with, which named the wrong keys.
    items: [
      { key: 'F1', label: 'phone' },
      { key: 'TAB', label: 'inventory' },
      { key: 'ALT', label: 'target' },
      { key: 'B', label: 'seatbelt' },
      { key: 'K', label: 'engine' },
      { key: 'G', label: 'seat' },
      { key: 'L', label: 'locks' },
      { key: 'X', label: 'handsup' },
    ],
  },

  /* ------------------------------------------------------------------ */
  /* 10. Links shown at the bottom                                       */
  /* ------------------------------------------------------------------ */
  links: {
    enabled: true,
    items: [
      { icon: 'discord', label: 'Discord', value: 'discord.gg/your-invite' },
      { icon: 'globe', label: 'Site', value: 'yourserver.com' },
      { icon: 'star', label: 'Free to play', value: '100 % free to play' },
    ],
  },

  /* ------------------------------------------------------------------ */
  /* 11. Progress readout                                                */
  /* ------------------------------------------------------------------ */
  progress: {
    showPercent: true,
    showStage: true,      // 'Chargement de la carte', ...
    showLogLine: true,    // file the game is currently reading
    showStageDots: true,  // the four stage markers above the bar
  },

  /* ------------------------------------------------------------------ */
  /* 12. Shutdown behaviour (read by client.lua)                         */
  /* ------------------------------------------------------------------ */
  runtime: {
    // true  -> v-loadscreen closes itself once the character is in the world.
    //          v-core has no separate resource that closes the screen, so this
    //          is the right default here: the client script holds the screen
    //          until v-core fires onPlayerLoaded, then fades it out.
    // false -> another resource calls ShutdownLoadingScreenNui() instead. Only
    //          set this if you add a multicharacter resource that does so.
    manualShutdown: true,

    // Seconds to wait after the world is ready before the fade (manualShutdown only).
    shutdownDelay: 1,

    // Keep the screen up for at least this long even on a fast load, so the
    // intro and the music have room to breathe (manualShutdown only).
    minimumDisplayTime: 6,

    // Show an ENTER button instead of closing on its own (manualShutdown only).
    enterButton: false,

    // Safety net: close the screen this many seconds after the session starts,
    // whatever happens. Stops a player being stuck forever if the resource that
    // normally closes it errors out. 0 disables it.
    failsafeTimeout: 180,
  },

  /* ------------------------------------------------------------------ */
  /* 13. Strings and tips, per language                                  */
  /* ------------------------------------------------------------------ */
  locales: {
    fr: {
      ui: {
        connecting: 'Connexion au serveur',
        loading: 'Chargement',
        ready: 'Prêt à jouer',
        enter: 'Entrer',
        tipLabel: 'Astuce',
        keybindsTitle: 'Raccourcis',
        playersLabel: 'en ligne',
        settings: 'Réglages',
        music: 'Musique',
        background: 'Arrière-plan',
        visuals: 'Effets',
        muted: 'Son coupé',
        volume: 'Volume',
        play: 'Lecture',
        pause: 'Pause',
        previous: 'Piste précédente',
        next: 'Piste suivante',
        mute: 'Couper le son',
        unmute: 'Rétablir le son',
        slideshow: 'Diaporama',
        nextBackground: 'Fond suivant',
        particles: 'Particules',
        grain: 'Grain',
        scanlines: 'Lignes CRT',
        performance: 'Mode performance',
        close: 'Fermer',
        stages: {
          core: 'Initialisation du moteur',
          map: 'Chargement de la carte',
          resources: 'Ressources du serveur',
          session: 'Ouverture de la session',
          done: 'Prêt',
        },
      },
      tips: [
        // -- prise en main -------------------------------------------------
        { icon: 'map', category: 'Emploi', text: 'Les jobs se prennent à la mairie.' },
        { icon: 'key', category: 'Papiers', text: 'Licences et papiers citoyen se trouvent dans le menu radial.' },
        { icon: 'car', category: 'Véhicules', text: 'La gestion de tes véhicules passe aussi par le menu radial.' },
        { icon: 'phone', category: 'Téléphone', text: 'Enregistre tes endroits favoris et partage-les depuis le téléphone.' },
        { icon: 'bulb', category: 'Astuce', text: 'Le menu radial regroupe la plupart des interactions. Garde-le sous la main.' },
        { icon: 'star', category: 'Serveur', text: '100 % free to play : aucune boutique en jeu, rien ne s\'achète.' },
        { icon: 'gauge', category: 'Performance', text: 'Règle l\'extended texture budget sur 50 % : le jeu tient mieux la distance.' },
        { icon: 'cpu', category: 'Performance', text: 'Un cache trop gros ralentit le chargement : vide-le de temps en temps.' },
        { icon: 'globe', category: 'Règlement', text: 'Le règlement complet est sur yourserver.com. Il évolue, reviens le lire.' },
        { icon: 'discord', category: 'Support', text: 'Un bug ? Note l\'heure et ce que tu faisais, puis signale-le sur le Discord.' },

        // -- cadre du serveur ----------------------------------------------
        { icon: 'shield', category: 'Accès', text: 'Serveur strictement 18+, et un seul compte par personne. Aucune exception.' },
        { icon: 'users', category: 'Roleplay', text: 'Serious RP : ton personnage a une histoire, des limites et une vie à perdre.' },
        { icon: 'info', category: 'Identité', text: 'Nom de personnage réaliste. Pas de célébrité, pas de fiction, pas de troll.' },
        { icon: 'clock', category: 'Temporalité', text: 'La ville vit à l\'heure réelle : la date en jeu est celle d\'aujourd\'hui.' },
        { icon: 'users', category: 'Personnage', text: 'Incarner un personnage d\'un autre genre demande un dossier et l\'accord du staff.' },
        { icon: 'shield', category: 'Respect', text: 'Aucun propos haineux, raciste, homophobe ou transphobe. Ni en RP, ni en HRP.' },

        // -- les grands interdits ------------------------------------------
        { icon: 'ban', category: 'Powergaming', text: 'Pas d\'acte surhumain : on ne soulève pas un véhicule, on n\'ignore pas un crash à 200.' },
        { icon: 'ban', category: 'Metagaming', text: 'Ce que tu lis sur Discord ou en stream n\'existe pas en ville. Ton perso ne le sait pas.' },
        { icon: 'ban', category: 'Mix-gaming', text: 'Pas de vocabulaire HRP en jeu. On parle de la loi de la ville, pas de "visa".' },
        { icon: 'shield', category: 'Fear RP', text: 'Une arme braquée sur toi, tu as peur. Tourner le dos ou foncer dans le tas, c\'est du No Fear.' },
        { icon: 'ban', category: 'FreeKill', text: 'Pas d\'agression gratuite : toute violence part d\'une interaction et d\'une raison.' },
        { icon: 'car', category: 'CarKill', text: 'Un véhicule n\'est pas une arme. Écraser des joueurs sans raison, c\'est du VDM.' },
        { icon: 'ban', category: 'Revenge Kill', text: 'On ne revient jamais armé sur le lieu de sa propre mort.' },
        { icon: 'clock', category: 'New Life Rule', text: 'Après un coma, tu oublies tout : les visages, les mots, la demi-heure d\'avant.' },
        { icon: 'heart', category: 'Pain RP', text: 'Une balle dans la jambe, ça se joue. Après un tonneau, tu restes au sol le temps qu\'il faut.' },
        { icon: 'ban', category: 'Combat Log', text: 'Se déconnecter pour fuir une arrestation ou un coma est lourdement sanctionné.' },
        { icon: 'ban', category: 'Double vocal', text: 'Discord en parallèle du vocal en jeu : formellement interdit.' },
        { icon: 'bolt', category: 'Bunny hop', text: 'Sauter en boucle pour aller plus vite ou esquiver des balles, c\'est du Low-RP.' },
        { icon: 'bulb', category: 'Use-bug', text: 'Un bug se signale en ticket, il ne s\'exploite pas. Traverser un mur pour s\'évader, c\'est ban.' },
        { icon: 'ban', category: 'Éthique', text: 'Pas de RP suicide, pas de personnage mineur, pas de torture ni d\'humiliation.' },
        { icon: 'ban', category: 'TOS', text: 'L\'ERP est interdit, en public comme en privé. Tolérance zéro.' },
        { icon: 'chat', category: 'Méta', text: 'Les infos RP passent par les outils en jeu : SMS, mail, radio. Jamais par Discord.' },

        // -- jouer la scène -------------------------------------------------
        { icon: 'star', category: 'Fair-play', text: 'Une scène perdue mais bien jouée vaut mieux qu\'une victoire arrachée. Play to lose.' },
        { icon: 'ban', category: 'Refus de scène', text: 'Une scène se joue jusqu\'au bout. Faire semblant d\'être AFK en plein braquage est sanctionné.' },
        { icon: 'users', category: 'Mass RP', text: 'La ville est pleine de témoins invisibles. Un braquage en plein jour, ça se prépare.' },
        { icon: 'car', category: 'Conduite', text: 'Pas de cascade ni de sportive sur le Chiliad. Sur les jantes, tu t\'arrêtes en moins de 100 m.' },
        { icon: 'chat', category: 'Litiges', text: 'Termine ta scène avant d\'ouvrir un ticket. Sans preuve vidéo, aucune plainte n\'est traitée.' },

        // -- roleplay illégal -----------------------------------------------
        { icon: 'mask', category: 'Racket', text: 'Sur un joueur : 50 % du cash et 50 % des items civils au maximum. L\'illégal se vole en entier.' },
        { icon: 'ban', category: 'Loot Kill', text: 'Mettre KO uniquement pour fouiller un inventaire est interdit.' },
        { icon: 'mask', category: 'Otages', text: 'Jamais de faux otage : ce doit être un civil neutre. Et la scène ne dépasse pas deux heures.' },
        { icon: 'key', category: 'Rançons', text: 'Plafonds : 5 000 $ pour un civil, 10 000 $ pour un agent public, 15 000 $ pour un dirigeant.' },
        { icon: 'clock', category: 'Braquages', text: 'ATM et supérette : 2 policiers en service. Cooldown de 2 h pour l\'un, 3 h pour l\'autre.' },
        { icon: 'clock', category: 'Banques', text: 'Fleeca, Pacific, Paleto et la bijouterie : 4 policiers en service minimum.' },
        { icon: 'bolt', category: 'Drive-by', text: 'Le drive-by sert à intimider, pas à tirer sur les gens. Et il se revendique immédiatement.' },
        { icon: 'users', category: 'Guerres', text: 'L\'escalade est obligatoire : provocation, puis brawl, et seulement ensuite les armes.' },
        { icon: 'ban', category: 'Explosifs', text: 'Un explosif est un acte terroriste : dossier validé, 2 policiers et 2 pompiers en service.' },
        { icon: 'car', category: 'Vol de véhicule', text: 'Tout véhicule est verrouillé : il faut du matériel et une scène. Le vol à la volée est interdit.' },
      ],
      keybinds: {
        phone: 'Téléphone',
        inventory: 'Inventaire',
        target: 'Interaction',
        seatbelt: 'Ceinture',
        engine: 'Moteur',
        seat: 'Changer de siège',
        locks: 'Verrouillage',
        handsup: 'Mains en l\'air',
      },
    },

    en: {
      ui: {
        connecting: 'Connecting to the server',
        loading: 'Loading',
        ready: 'Ready to play',
        enter: 'Enter',
        tipLabel: 'Tip',
        keybindsTitle: 'Keybinds',
        playersLabel: 'online',
        settings: 'Settings',
        music: 'Music',
        background: 'Background',
        visuals: 'Effects',
        muted: 'Muted',
        volume: 'Volume',
        play: 'Play',
        pause: 'Pause',
        previous: 'Previous track',
        next: 'Next track',
        mute: 'Mute',
        unmute: 'Unmute',
        slideshow: 'Slideshow',
        nextBackground: 'Next background',
        particles: 'Particles',
        grain: 'Grain',
        scanlines: 'CRT lines',
        performance: 'Performance mode',
        close: 'Close',
        stages: {
          core: 'Starting the engine',
          map: 'Loading the map',
          resources: 'Server resources',
          session: 'Opening the session',
          done: 'Ready',
        },
      },
      tips: [
        // -- getting started -------------------------------------------------
        { icon: 'map', category: 'Jobs', text: 'Jobs are picked up at the city hall.' },
        { icon: 'key', category: 'Papers', text: 'Licences and citizen paperwork live in the radial menu.' },
        { icon: 'car', category: 'Vehicles', text: 'Managing your vehicles also goes through the radial menu.' },
        { icon: 'phone', category: 'Phone', text: 'Save your favourite spots and share them from the phone.' },
        { icon: 'bulb', category: 'Tip', text: 'The radial menu holds most interactions. Keep it close.' },
        { icon: 'star', category: 'Server', text: '100 % free to play: no in game shop, nothing is for sale.' },
        { icon: 'gauge', category: 'Performance', text: 'Set the extended texture budget to 50 %, the game holds up much better.' },
        { icon: 'cpu', category: 'Performance', text: 'An oversized cache slows the load down. Clear it once in a while.' },
        { icon: 'globe', category: 'Rules', text: 'The full rulebook is on yourserver.com. It changes, so come back to it.' },
        { icon: 'discord', category: 'Support', text: 'Found a bug? Note the time and what you were doing, then report it on Discord.' },

        // -- the frame -------------------------------------------------------
        { icon: 'shield', category: 'Access', text: 'Strictly 18+, and one account per person. No exceptions.' },
        { icon: 'users', category: 'Roleplay', text: 'Serious RP: your character has a story, limits, and a life to lose.' },
        { icon: 'info', category: 'Identity', text: 'Realistic character names only. No celebrities, no fiction, no trolling.' },
        { icon: 'clock', category: 'Timeline', text: 'The city runs on real time: the in game date is today\'s date.' },
        { icon: 'users', category: 'Character', text: 'Playing a character of another gender needs an application and staff approval.' },
        { icon: 'shield', category: 'Respect', text: 'No hateful, racist, homophobic or transphobic talk. In character or out of it.' },

        // -- the hard lines --------------------------------------------------
        { icon: 'ban', category: 'Powergaming', text: 'No superhuman acts: you do not lift a car, and you do not shrug off a 200 km/h crash.' },
        { icon: 'ban', category: 'Metagaming', text: 'What you read on Discord or a stream does not exist in the city. Your character does not know it.' },
        { icon: 'ban', category: 'Mixgaming', text: 'No out of character vocabulary in game. You talk about city law, not about "a visa".' },
        { icon: 'shield', category: 'Fear RP', text: 'A gun on you means fear. Turning your back or rushing in is No Fear.' },
        { icon: 'ban', category: 'FreeKill', text: 'No free aggression: violence starts from an interaction and a reason.' },
        { icon: 'car', category: 'CarKill', text: 'A vehicle is not a weapon. Running players over without reason is VDM.' },
        { icon: 'ban', category: 'Revenge Kill', text: 'You never come back armed to the place you died.' },
        { icon: 'clock', category: 'New Life Rule', text: 'After a coma you forget everything: the faces, the words, the half hour before.' },
        { icon: 'heart', category: 'Pain RP', text: 'A bullet in the leg gets played. After a rollover you stay down as long as it takes.' },
        { icon: 'ban', category: 'Combat Log', text: 'Disconnecting to dodge an arrest or a coma is heavily punished.' },
        { icon: 'ban', category: 'Double voice', text: 'Discord alongside in game voice is strictly forbidden.' },
        { icon: 'bolt', category: 'Bunny hop', text: 'Jumping on loop to move faster or dodge bullets is low RP.' },
        { icon: 'bulb', category: 'Bug abuse', text: 'A bug gets reported, not exploited. Walking through a wall to escape is a ban.' },
        { icon: 'ban', category: 'Ethics', text: 'No suicide RP, no underage characters, no torture and no humiliation.' },
        { icon: 'ban', category: 'TOS', text: 'Erotic RP is forbidden, in public and in private. Zero tolerance.' },
        { icon: 'chat', category: 'Meta', text: 'RP information travels through in game tools: texts, mail, radio. Never Discord.' },

        // -- playing the scene ------------------------------------------------
        { icon: 'star', category: 'Fair play', text: 'A scene lost but well played beats a scene won by force. Play to lose.' },
        { icon: 'ban', category: 'Ducking out', text: 'A scene is played to the end. Pretending to be away mid heist is punished.' },
        { icon: 'users', category: 'Mass RP', text: 'The city is full of invisible witnesses. A daylight robbery needs preparing.' },
        { icon: 'car', category: 'Driving', text: 'No stunts, no sports cars up Chiliad. On the rims, you stop within 100 m.' },
        { icon: 'chat', category: 'Disputes', text: 'Finish your scene before opening a ticket. Without video proof no report is handled.' },

        // -- criminal roleplay -------------------------------------------------
        { icon: 'mask', category: 'Robbing', text: 'From a player: 50 % of the cash and 50 % of civilian items at most. Illegal goods go entirely.' },
        { icon: 'ban', category: 'Loot Kill', text: 'Downing someone purely to search their inventory is forbidden.' },
        { icon: 'mask', category: 'Hostages', text: 'Never a fake hostage: it has to be a neutral civilian. And the scene stops at two hours.' },
        { icon: 'key', category: 'Ransoms', text: 'Caps: $5,000 for a civilian, $10,000 for a public agent, $15,000 for a director.' },
        { icon: 'clock', category: 'Robberies', text: 'ATMs and stores: 2 officers on duty. Cooldown of 2 h for one, 3 h for the other.' },
        { icon: 'clock', category: 'Banks', text: 'Fleeca, Pacific, Paleto and the jewellery store: 4 officers on duty minimum.' },
        { icon: 'bolt', category: 'Drive-by', text: 'A drive-by intimidates, it does not shoot people. And it is claimed immediately.' },
        { icon: 'users', category: 'Wars', text: 'Escalation is mandatory: provocation, then a brawl, and only then weapons.' },
        { icon: 'ban', category: 'Explosives', text: 'An explosive is a terrorist act: approved application, 2 officers and 2 firefighters on duty.' },
        { icon: 'car', category: 'Car theft', text: 'Every vehicle is locked: you need tools and a scene. Grabbing one on the fly is forbidden.' },
      ],
      keybinds: {
        phone: 'Phone',
        inventory: 'Inventory',
        target: 'Interaction',
        seatbelt: 'Seatbelt',
        engine: 'Engine',
        seat: 'Change seat',
        locks: 'Vehicle locks',
        handsup: 'Hands up',
      },
    },
  },
};
