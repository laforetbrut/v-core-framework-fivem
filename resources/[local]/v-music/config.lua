-- v-music | shared config
-- Boomboxes, jukeboxes and the car stereo. Built on the same rule as `v-3dsound`: the
-- server broadcasts the intent, each client plays it locally and attenuates by its own
-- distance. Nothing streams through the server.
--
-- Jukeboxes are a `v-world` domain (`jukebox`), so an operator places them from the admin
-- panel like every other piece of world content.
Config = {}

-- One key, context-dependent: in a vehicle it is the stereo, at a jukebox it is the
-- jukebox, otherwise it is your boombox. Two keys would be one for the player to forget.
Config.Key = 'F4'

Config.Distance = 2.5           -- how close you must be to touch a source

-- A boombox is an item you drop; it becomes a source at your feet.
Config.Boombox = {
    item    = 'boombox',
    prop    = 'prop_boombox_01',
    range   = 35.0,
    maxPerPlayer = 1,
}

-- The car stereo is bound to a vehicle you have keys for. Audible outside, quieter, which
-- is most of the fun.
Config.Vehicle = {
    range       = 22.0,
    outsideMult = 0.45,         -- volume outside the car, relative to inside
}

Config.Jukebox = { range = 28.0 }

Config.DefaultVolume = 0.6
Config.MaxRange      = 80.0     -- ceiling on any source, whatever it asks for

-- **Arbitrary URL playback is a moderation problem, not a technical one.** A server that
-- lets anyone stream anything to everyone in earshot will spend its first week moderating
-- audio, so the allow-list starts narrow and every play is logged with who asked for it.
Config.AllowedHosts = {
    'youtube.com', 'www.youtube.com', 'youtu.be',
    'soundcloud.com', 'w.soundcloud.com',
}

-- Fixed jukeboxes seeded into `world_jukebox`. Real Los Santos venues.
Config.Jukeboxes = {
    { id = 'unicorn',  label = 'Vanilla Unicorn',   x = 127.9,   y = -1298.3, z = 29.2 },
    { id = 'yellowjack', label = 'Yellow Jack Inn', x = 1986.0,  y = 3053.0,  z = 47.2 },
    { id = 'tequilala', label = 'Tequi-la-la',      x = -561.5,  y = 286.5,   z = 82.2 },
    { id = 'bahama',   label = 'Bahama Mamas',      x = -1388.0, y = -586.6,  z = 30.3 },
}
