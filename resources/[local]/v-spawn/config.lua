-- v-spawn | shared config
Config = {}

Config.Debug = false

-- Character creation happens INSIDE a store interior (each new player is
-- already isolated in a private routing bucket by v-core).
Config.CreatorCoords = vector4(75.05, -1389.9, 29.38, 185.0)   -- Binco, Textile City (interior)

-- Freemode models by sex (0 = male, 1 = female).
Config.Models = { [0] = 'mp_m_freemode_01', [1] = 'mp_f_freemode_01' }

-- First-spawn choices offered right after character creation.
Config.SpawnPoints = {
    { key = 'airport', i18n = 'spawn.airport', sub = 'spawn.airport_sub', coords = vector4(-1037.66, -2737.98, 20.17, 329.3) },
    { key = 'prison',  i18n = 'spawn.prison',  sub = 'spawn.prison_sub',  coords = vector4(1846.2, 2585.9, 45.67, 269.0) },
    { key = 'sandy',   i18n = 'spawn.sandy',   sub = 'spawn.sandy_sub',   coords = vector4(1332.6, 4274.5, 33.6, 100.0) },
}

-- Fallback spawn (also used if a returning character has no saved position).
Config.Spawn = vector4(-1037.66, -2737.98, 20.17, 329.3)

-- Extra time (ms) the player is held frozen at the destination after the ground is
-- found, so the world + all NUIs finish streaming/warming up before control is handed
-- over — reduces the "everything is laggy for the first minute after spawn" window.
-- Raise it if players still report a laggy first minute; 0 disables the hold.
Config.PostSpawnHold = 3000

-- Editor ranges.
Config.Max = {
    hair = 73, eyebrows = 33, beard = 28, faceParents = 45,
    eyeColor = 31, hairColor = 63, tops = 300, undershirt = 200,
    pants = 200, shoes = 100, arms = 200,
}
