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

-- ── In hand ────────────────────────────────────────────────────
-- A phone you are using is a phone you are holding: a prop in the hand and an animation
-- to match, while you stay free to walk and drive. Open on foot and you browse one-handed;
-- open in a car and the prop still shows. A call raises it to the ear.
Config.Hold = {
    prop   = 'prop_amb_phone',           -- base-game phone prop, attached to the right hand
    bone   = 28422,                      -- SKEL_R_Hand
    pos    = vec3(0.0, 0.0, 0.0),
    rot    = vec3(0.0, 0.0, 0.0),
    dict   = 'cellphone@',
    browse = 'cellphone_text_read_base', -- one-handed, looking at the screen
    call   = 'cellphone_call_listen_base', -- to the ear
    -- Disabled while the phone is up so a click on the screen does not fire a gun, and the
    -- mouse drives the cursor instead of spinning the camera. Movement, sprint, jump and
    -- every vehicle control are left untouched, so you keep walking and driving.
    block  = { 1, 2, 24, 25, 47, 257, 263, 264, 45, 140, 141, 142, 143, 37, 44, 68, 69, 70, 91, 92 },
}

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
    -- `required` cannot be removed: a phone with no Phone app is a brick, and a phone
    -- with no store cannot get anything back.
    -- `optional` is NOT installed to begin with - it has to be downloaded, which is the
    -- only honest way to make a store mean something.
    -- `category` is what the store sorts by.
    -- The order below IS the home screen on a phone nobody has rearranged yet, and it is
    -- grouped the way a real one ships: the four you reach for without thinking in the
    -- dock, then communication and travel, capture and media, life and work, the small
    -- tools, anything a job unlocks, the downloads, and the store and settings last.
    -- A player who rearranges their apps overrides this; it is only ever the default.
    { id = 'phone',    label = 'app.phone',    icon = 'phone',    owner = 'v-phone',    slot = 1, dock = true,
      required = true, category = 'essentials' },
    { id = 'messages', label = 'app.messages', icon = 'messages', owner = 'v-phone',    slot = 2, dock = true,
      required = true, category = 'essentials' },
    { id = 'contacts', label = 'app.contacts', icon = 'contacts', owner = 'v-phone',    slot = 3, dock = true,
      required = true, category = 'essentials' },
    { id = 'bank',     label = 'app.bank',     icon = 'bank',     owner = 'v-banking',  slot = 4, dock = true,
      category = 'finance' },
    { id = 'mail',     label = 'app.mail',     icon = 'mail',     owner = 'v-phone',    slot = 5,
      category = 'work' },
    { id = 'maps',     label = 'app.maps',     icon = 'map',      owner = 'v-world',    slot = 6,
      category = 'travel' },
    { id = 'camera',   label = 'app.camera',   icon = 'camera',   owner = 'v-phone',    slot = 7,
      category = 'utilities' },
    { id = 'gallery',  label = 'app.gallery',  icon = 'images',   owner = 'v-phone',    slot = 8,
      category = 'utilities' },
    { id = 'music',    label = 'app.music',    icon = 'music',    owner = 'v-music',    slot = 9,
      category = 'entertainment' },
    { id = 'garage',   label = 'app.garage',   icon = 'garage',   owner = 'v-vehicles', slot = 10,
      category = 'travel' },
    { id = 'property', label = 'app.property', icon = 'house',    owner = 'v-housing',  slot = 11,
      category = 'utilities' },
    -- Police only by default. The operator can open it up, or gate something else the
    -- same way, from Editor -> Phone apps.
    { id = 'wallet',   label = 'app.wallet',   icon = 'wallet',   owner = 'v-licenses', slot = 12,
      category = 'finance' },
    { id = 'jobs',     label = 'app.jobs',     icon = 'jobs',     owner = 'v-cityhall', slot = 13,
      category = 'work' },
    { id = 'health',   label = 'app.health',   icon = 'heart',    owner = 'v-status',   slot = 14,
      category = 'health' },
    { id = 'reminders', label = 'app.reminders', icon = 'check',  owner = 'v-phone',    slot = 15,
      category = 'utilities' },
    { id = 'calc',     label = 'app.calc',     icon = 'calc',     owner = 'v-phone',    slot = 16,
      category = 'utilities' },
    { id = 'mdt',      label = 'app.mdt',      icon = 'shield',   owner = 'v-police',   slot = 17,
      -- Job apps get their own aisle: it is only in the store at all for the people
      -- who hold the job, so it has no business sitting under Work next to Jobs.
      job = 'police', category = 'duty' },
    { id = 'bleeter',  label = 'app.bleeter',  icon = 'bleet',    owner = 'v-social',   slot = 18,
      optional = true, category = 'social' },
    { id = 'snap',     label = 'app.snap',     icon = 'snap',     owner = 'v-social',   slot = 19,
      optional = true, category = 'social' },
    { id = 'hush',     label = 'app.hush',     icon = 'hush',     owner = 'v-social',   slot = 20,
      optional = true, category = 'social' },
    { id = 'store',    label = 'app.store',    icon = 'store',    owner = 'v-phone',    slot = 21,
      required = true, category = 'essentials' },
    { id = 'settings', label = 'app.settings', icon = 'settings', owner = 'v-phone',    slot = 22,
      required = true, category = 'essentials' },
}

-- What the store groups by. The order here is the order of the sections.
Config.Categories = { 'social', 'finance', 'utilities', 'travel', 'work', 'duty',
                      'entertainment', 'health', 'essentials' }

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

-- ── Mail ───────────────────────────────────────────────────────
-- Addresses are chosen once and belong to the character. The domains are the game's own
-- companies, because inventing a webmail brand would break the world every other module
-- is set in.
Config.Mail = {
    -- The domains offered when a player creates their address. Add, remove or reorder
    -- freely: the first one is simply what the picker starts on, and the server accepts an
    -- address only if its domain is in this list. Existing addresses are never touched by a
    -- change here, so removing a domain stops new sign-ups on it without breaking anyone.
    domains  = { 'ls.com', 'eyefind.info', 'lifeinvader.com', 'bilkinton.com' },
    maxSubject = 80,
    maxBody    = 2000,
    maxTo      = 10,       -- a group mail, not a mailing list
    localMin   = 3,
    localMax   = 20,
}

-- ── Sounds ─────────────────────────────────────────────────────
-- Ringtones and alerts are played by the page, not by the game, so a player can point one
-- at their own MP3. The built-ins are synthesised in the browser - no audio ships with the
-- resource, and nothing is fetched unless somebody chose a link.
--
-- A custom tone is a URL a client will fetch, so the hosts are an operator decision, the
-- same rule as wallpapers and avatars.
Config.Sounds = {
    ringtones = { 'classic', 'chime', 'pulse', 'radar', 'none' },
    alerts    = { 'ping', 'pop', 'tick', 'none' },
    allowCustom = true,
    hosts = {
        'cdn.discordapp.com', 'media.discordapp.net',
        'raw.githubusercontent.com', 'github.com',
        'files.catbox.moe', 'i.imgur.com',
    },
}

-- ── AirDrop ────────────────────────────────────────────────────
-- Send a contact, your number or a photo to a nearby phone. Both ends must have
-- Bluetooth on in the control centre, and be within range - the same two conditions the
-- real thing needs to see a device at all.
Config.Airdrop = { range = 12.0, offerTtl = 30 }

-- ── Battery ────────────────────────────────────────────────────
-- Eight real-world hours from full to flat, which is roughly what a phone does. The
-- number is a setting because "how long is a session here" is a server's answer, not
-- ours.
--
-- **It only drains while the player is connected.** A phone genuinely goes flat in a
-- drawer, but so does the ability to charge it: coming back from a week away to a dead
-- phone and no way to have prevented it is a punishment for logging off.
Config.Battery = {
    hoursToEmpty = 8.0,     -- idle, phone closed
    screenMultiplier = 3.0, -- how much faster it drains with the screen on
    chargeMinutes = 45.0,   -- flat to full at a charger
    lowAt = 20,             -- first warning
    criticalAt = 5,
}

-- Charging happens at these, and also in any vehicle and inside a property you hold a key
-- to. Those two are code, because they follow the player rather than a coordinate.
-- SEED DATA ONLY: chargers live in `world_chargers` and are edited from the admin panel.
Config.Chargers = {
    { id = 'ch_lsia',      label = 'LSIA, arrivals hall',    x = -1037.0, y = -2737.0, z = 20.2, radius = 8.0 },
    { id = 'ch_legion',    label = 'Legion Square kiosk',    x = 195.0,   y = -933.0,  z = 30.7, radius = 6.0 },
    { id = 'ch_pillbox',   label = 'Pillbox Hill Medical',   x = 306.0,   y = -595.0,  z = 43.3, radius = 8.0 },
    { id = 'ch_paleto',    label = 'Paleto Bay, sheriff',    x = -448.0,  y = 6013.0,  z = 31.7, radius = 6.0 },
    { id = 'ch_sandy',     label = 'Sandy Shores, clinic',   x = 1839.0,  y = 3672.0,  z = 34.3, radius = 8.0 },
    { id = 'ch_vespucci',  label = 'Vespucci boardwalk',     x = -1223.0, y = -1493.0, z = 4.4,  radius = 6.0 },
}

-- Where the network does not reach. `bars` is the CEILING inside the zone: 0 means no
-- service at all. Real places, chosen because they are places a story would put you.
-- SEED DATA ONLY: edited from the admin panel -> Editor -> Dead zones.
Config.DeadZones = {
    { id = 'dz_chiliad',   label = 'Mount Chiliad',          x = 501.0,   y = 5604.0,  z = 797.0, radius = 700.0, bars = 0 },
    { id = 'dz_raton',     label = 'Raton Canyon',           x = -1500.0, y = 4400.0,  z = 40.0,  radius = 500.0, bars = 0 },
    { id = 'dz_zancudo',   label = 'Fort Zancudo',           x = -2100.0, y = 3200.0,  z = 32.0,  radius = 900.0, bars = 0 },
    { id = 'dz_humane',    label = 'Humane Labs',            x = 3600.0,  y = 3700.0,  z = 30.0,  radius = 400.0, bars = 0 },
    { id = 'dz_wilderness',label = 'Chiliad Wilderness',     x = -700.0,  y = 5000.0,  z = 100.0, radius = 900.0, bars = 1 },
    { id = 'dz_senora',    label = 'Grand Senora Desert',    x = 1400.0,  y = 2800.0,  z = 60.0,  radius = 800.0, bars = 1 },
    { id = 'dz_tunnel_ls', label = 'Los Santos tunnels',     x = 800.0,   y = -1300.0, z = -40.0, radius = 260.0, bars = 0 },
    { id = 'dz_mine',      label = 'Davis Quartz',           x = 2900.0,  y = 2800.0,  z = 40.0,  radius = 350.0, bars = 1 },
}
