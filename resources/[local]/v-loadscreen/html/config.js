/* v-loadscreen | config.js — the loading screen is configured HERE.
 *
 * A loading screen runs before any resource has started, so it cannot ask v-core for
 * settings or read a Lua config: it is a plain web page loaded by the client. This file
 * is therefore its config file, and it is deliberately exhaustive — layout, palette,
 * background, copy and tips are all here, with nothing hardcoded in the markup.
 *
 * Change LAYOUT to restyle the whole screen. Change THEME to recolour it. Both are
 * previewable by opening html/index.html in a browser.
 */
window.LOADSCREEN_CONFIG = {

  /* ── Layout ────────────────────────────────────────────────────
   * Where the brand and the progress panel sit, and how they are composed.
   *   'centre'    brand above a centred panel                (default, cinematic)
   *   'left'      everything stacked bottom-left             (lets the art breathe)
   *   'right'     everything stacked bottom-right
   *   'split'     brand left, panel right, vertically centred
   *   'bottom'    slim full-width bar pinned to the bottom   (minimal)
   *   'top'       slim full-width bar pinned to the top
   *   'card'      one contained card, centred                (compact)
   */
  layout: 'centre',

  /* ── Background ────────────────────────────────────────────────
   * kind: 'video' | 'image' | 'gradient' | 'solid'
   * A video needs `bg.mp4` + `poster.jpg` beside this file.
   */
  background: {
    kind: 'video',
    video: 'bg.mp4',
    poster: 'poster.jpg',
    image: 'poster.jpg',
    /* Used by 'gradient'. Any CSS gradient is valid. */
    gradient: 'radial-gradient(120% 100% at 50% 0%, #1d1409 0%, #0b0a08 65%)',
    solid: '#0b0a08',
    /* How much the background is dimmed behind the content, 0-1. */
    dim: 0.55,
    /* Slow zoom on the background while loading. */
    kenBurns: true
  },

  /* ── Palette ───────────────────────────────────────────────────
   * Mirrors v-ui's presets so the loading screen matches the in-game UI. Set `preset` to
   * one of them, or set `accent`/`bg`/`text` directly to override.
   */
  theme: {
    preset: 'ember',
    presets: {
      ember:    { accent: '#ff7a1a', accent2: '#f04e00', bg: '#0b0a08', panel: '#16130f', text: '#f4efe8' },
      midnight: { accent: '#4a9fe0', accent2: '#2c6fb0', bg: '#070a0f', panel: '#101720', text: '#e8eef4' },
      crimson:  { accent: '#e0323c', accent2: '#9c1622', bg: '#0c0708', panel: '#191012', text: '#f6ecec' },
      verdant:  { accent: '#57b364', accent2: '#2f7a3c', bg: '#070b08', panel: '#101711', text: '#ecf4ed' },
      violet:   { accent: '#a45ad8', accent2: '#6d2ea0', bg: '#0a070d', panel: '#171021', text: '#f1ecf6' },
      slate:    { accent: '#8a94a6', accent2: '#5b6474', bg: '#0a0b0d', panel: '#15171b', text: '#eceef2' }
    },
    /* Leave '' to use the preset. Any of these overrides it. */
    accent: '',
    bg: '',
    text: '',
    /* Corner roundness multiplier, 0 = square. */
    radius: 1.0,
    /* Panel opacity, 0-1. */
    panelAlpha: 0.94
  },

  /* ── Effects ───────────────────────────────────────────────────
   * All optional: turn them off on a weak client, or for a cleaner look.
   */
  effects: {
    grain: true,        /* film grain over the whole screen */
    vignette: true,     /* darkened edges */
    scanline: true,     /* the slow horizontal sweep */
    brackets: true,     /* corner brackets on the panel (the "Field Case" signature) */
    motion: 1.0         /* animation speed multiplier; 0 disables all motion */
  },

  /* ── Copy ──────────────────────────────────────────────────────
   * Everything readable on the screen. `lang` picks which set is used.
   */
  lang: 'fr',
  text: {
    fr: {
      kicker: 'Los Santos Roleplay',
      title: 'PROJET',
      titleAccent: 'R',
      panel: 'Démarrage',
      signature: 'projet r · laforetbrut',
      tipTag: 'Astuce',
      /* Shown in order as loading advances. */
      stages: [
        'Connexion au serveur…',
        'Chargement des ressources…',
        'Synchronisation du monde…',
        'Presque prêt…'
      ]
    },
    en: {
      kicker: 'Los Santos Roleplay',
      title: 'PROJET',
      titleAccent: 'R',
      panel: 'System Boot',
      signature: 'projet r · laforetbrut',
      tipTag: 'Tip',
      stages: [
        'Connecting to the server…',
        'Loading resources…',
        'Syncing the world…',
        'Almost there…'
      ]
    }
  },

  /* ── Tips ──────────────────────────────────────────────────────
   * Rotated while loading. Add your own freely; keep them short.
   */
  tips: {
    fr: [
      'Maintiens Alt gauche pour ouvrir l\'œil d\'interaction sur ce que tu regardes.',
      'TAB ouvre ton inventaire. Fais glisser un objet sur la barre rapide pour l\'y placer.',
      'Ta voiture s\'use : le compteur, les pièces et les dégâts sont mémorisés.',
      'Fais le plein avant de partir loin — la panne sèche est réelle.',
      'La mairie délivre tes papiers. Le permis s\'obtient à l\'auto-école.',
      'Une pièce usée se sent avant de se voir : moins de puissance, moins de freins.',
      'Les électriques se rechargent aux bornes ; charger à 80 % est bien plus rapide.',
      'Ranger ta voiture au garage sauvegarde son état exact.',
      'Le menu admin est en F10 pour le staff.',
      'Chaque texte du serveur existe en français et en anglais.'
    ],
    en: [
      'Hold Left-Alt to open the interaction eye on whatever you are looking at.',
      'TAB opens your inventory. Drag an item onto the hotbar to place it there.',
      'Your car wears out: the odometer, its parts and its damage are all remembered.',
      'Fill up before a long trip — running dry is real.',
      'The city hall issues your papers. The driving licence comes from the school.',
      'A worn part is felt before it is seen: less power, weaker brakes.',
      'Electric cars charge at the posts; charging to 80% is far quicker than to 100%.',
      'Parking in a garage saves your car\'s exact condition.',
      'Staff: the admin panel is on F10.',
      'Every string on this server exists in French and English.'
    ]
  },
  /* Seconds each tip stays on screen. */
  tipInterval: 6
};
