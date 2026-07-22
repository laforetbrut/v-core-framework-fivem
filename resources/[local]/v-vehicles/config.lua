-- v-vehicles | shared config
-- The ownership + persistence layer every other vehicle module sits on.
-- Nothing else in the framework may spawn an OWNED vehicle: go through SpawnOwned.
Config = {}

-- Plate format. GTA plates are 8 characters max; we mint 2 letters + 5 digits so a
-- player plate is visually distinct from the random NPC ones.
Config.PlatePrefix = 'VR'
Config.PlateDigits = 5

-- How often a spawned owned vehicle writes its condition back to the DB (seconds).
-- The state is also written on store, on despawn and on disconnect, so this is only
-- a safety net against a crash.
Config.SaveInterval = 120

-- Fuel drain per minute of engine-on time, as a percentage. Tuned low: a full tank
-- is roughly 45 minutes of continuous driving.
Config.FuelDrain = 2.2

-- Keys.
Config.Keys = {
    -- A driver without keys cannot start the engine. They can still sit in the seat
    -- and be driven around — stealing a car is a lockpick/hotwire problem, not a
    -- "you cannot touch it" problem.
    lockEngine   = true,
    -- Seconds a hotwire attempt takes (used by v-police / crime modules later).
    hotwireTime  = 12,
    -- Keys are held in memory only: they are a session-scoped courtesy ("hold my car"),
    -- not an ownership record. Ownership lives in character_vehicles.citizenid.
    persist      = false,
}

-- Vehicle state values stored in character_vehicles.state.
Config.State = { OUT = 0, GARAGED = 1, IMPOUND = 2 }

-- Mod slots persisted with a vehicle. Anything not listed here is not restored, so add
-- to this list rather than inventing a parallel table elsewhere.
Config.ModSlots = {
    0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16,
    17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31,
    32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 48,
}
