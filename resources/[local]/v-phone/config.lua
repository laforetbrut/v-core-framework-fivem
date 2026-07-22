-- v-phone | shared config
-- iFruit. The framework has no player chat commands by design, which makes the phone the
-- surface most of the game is played through.
--
-- **The phone is a shell, not a feature.** Every app is a thin view over the module that
-- already owns its data: the bank app calls v-banking, it does not keep a balance. The
-- moment an app holds its own copy of anything there are two sources of truth, and one of
-- them is wrong. Messages and contacts are the only things v-phone owns outright.
Config = {}

-- Open / close the phone.
Config.Key = 'F1'

-- ── Numbers ────────────────────────────────────────────────────
-- A number is how contacts, calls and messages address each other. Never the citizen id:
-- that is a database key, and a player should not be trading it.
--
-- `#` is replaced by a random digit. Anything else is kept, so a server can use its own
-- shape. Los Santos numbers in GTA are 555-xxxx, which is what this ships as.
Config.NumberFormat = '555-####'

-- ── Messages ───────────────────────────────────────────────────
Config.Messages = {
    maxLength   = 250,      -- characters
    pageSize    = 40,       -- messages loaded per conversation
    retentionDays = 30,     -- 0 keeps everything for ever
}

-- ── Calls ──────────────────────────────────────────────────────
-- The phone does NO audio. v-voice owns the Mumble channel; the phone only decides who is
-- talking to whom, and it decides it on the server so that ringing somebody does not
-- depend on the caller knowing where they are.
Config.Calls = {
    ringSeconds = 30,       -- unanswered calls give up after this
    maxMinutes  = 30,       -- hard ceiling on one call, so a forgotten call is not for ever
}

-- ── Apps ───────────────────────────────────────────────────────
-- SEED DATA ONLY: apps live in `world_apps` (owned by v-world) and are enabled, gated and
-- reordered from the admin panel -> Editor -> Apps.
--
-- `owner` is the module the app is a view of, and an app whose owner is stopped is not
-- shown: an app that opens onto nothing is worse than an app that is not there.
Config.Apps = {
    { id = 'phone',    label = 'app.phone',    icon = 'phone',    owner = 'v-phone',    slot = 1, dock = true, required = true },
    { id = 'messages', label = 'app.messages', icon = 'messages', owner = 'v-phone',    slot = 2, dock = true, required = true },
    { id = 'contacts', label = 'app.contacts', icon = 'contacts', owner = 'v-phone',    slot = 3, dock = true },
    { id = 'bank',     label = 'app.bank',     icon = 'bank',     owner = 'v-banking',  slot = 4, dock = true },
    { id = 'garage',   label = 'app.garage',   icon = 'garage',   owner = 'v-vehicles', slot = 5 },
    { id = 'wallet',   label = 'app.wallet',   icon = 'wallet',   owner = 'v-licenses', slot = 6 },
    { id = 'jobs',     label = 'app.jobs',     icon = 'jobs',     owner = 'v-cityhall', slot = 7 },
    { id = 'maps',     label = 'app.maps',     icon = 'map',      owner = 'v-world',    slot = 8 },
    { id = 'music',    label = 'app.music',    icon = 'music',    owner = 'v-music',    slot = 9 },
    { id = 'property', label = 'app.property', icon = 'house',    owner = 'v-housing',  slot = 10 },
    -- Police only by default. The operator can open it up, or gate something else the
    -- same way, from Editor -> Phone apps.
    { id = 'mdt',      label = 'app.mdt',      icon = 'shield',   owner = 'v-police',   slot = 11,
      job = 'police' },
    { id = 'calc',     label = 'app.calc',     icon = 'calc',     owner = 'v-phone',    slot = 12 },
    { id = 'health',   label = 'app.health',   icon = 'heart',    owner = 'v-status',   slot = 13 },
    { id = 'reminders', label = 'app.reminders', icon = 'check',  owner = 'v-phone',    slot = 14 },
    { id = 'camera',   label = 'app.camera',   icon = 'camera',   owner = 'v-phone',    slot = 15 },
    { id = 'store',    label = 'app.store',    icon = 'store',    owner = 'v-phone',    slot = 13,
      required = true },
    { id = 'settings', label = 'app.settings', icon = 'settings', owner = 'v-phone',    slot = 20,
      required = true },
}

-- ── Look ───────────────────────────────────────────────────────
-- The chrome is the phone's; the accent, panel and radius come from v-ui, so a server that
-- themes the framework purple gets a purple phone rather than an orange rectangle in a
-- purple world.
Config.Wallpapers = { 'dune', 'grid', 'night', 'ember' }
Config.DefaultWallpaper = 'ember'

-- iOS 27's transparency slider, as a starting value: 0 is ultra clear glass, 100 is
-- fully tinted. Players move it themselves in Settings; this is only where they begin.
Config.DefaultGlass = 55

-- ── Custom wallpapers ──────────────────────────────────────────
-- A player may point the phone at an image on the web. That is a URL a client will fetch,
-- so the hosts it may fetch from are an OPERATOR decision, exactly as they are for music.
-- It ships narrow on purpose: an open list is a way to make somebody's client load
-- anything at all.
Config.WallpaperHosts = {
    'i.imgur.com', 'imgur.com',
    'cdn.discordapp.com', 'media.discordapp.net',
    'i.ibb.co', 'raw.githubusercontent.com',
}

-- How a linked image is fitted. `cover` fills the screen and crops; `contain` shows all of
-- it with bars. Both are offered because neither is right for every picture.
Config.WallpaperFit = 'cover'

-- The device itself. Players with small screens want it smaller, and left-handers want it
-- on the other side; neither is worth making them live without.
Config.DeviceSize = 1.0        -- 0.75 .. 1.15
Config.DeviceSide = 'right'    -- right | left
