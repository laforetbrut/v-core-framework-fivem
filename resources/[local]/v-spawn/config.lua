-- v-spawn | shared config
Config = {}

Config.Debug = false

-- Where character creation happens (quiet spot; a routing bucket can be added later).
Config.CreatorCoords = vector4(-1041.0, -2745.0, 21.36, 328.0)

-- Freemode models by sex (0 = male, 1 = female).
Config.Models = { [0] = 'mp_m_freemode_01', [1] = 'mp_f_freemode_01' }

-- Where a freshly created / returning character spawns.
Config.Spawn = vector4(-1037.66, -2737.98, 20.17, 329.3)

-- Editor ranges.
Config.Max = {
    hair = 73, eyebrows = 33, beard = 28, faceParents = 45,
    eyeColor = 31, hairColor = 63, tops = 300, undershirt = 200,
    pants = 200, shoes = 100, arms = 200,
}
