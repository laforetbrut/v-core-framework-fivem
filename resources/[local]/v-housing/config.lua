-- v-housing | shared config
-- Property, and motels as a tenancy of it rather than a second module. Same shells, same
-- routing buckets, same stash, same key model; rented instead of owned, with a smaller
-- stash and no garage. That is the entire difference, and all three are columns.
--
-- SEED DATA ONLY: properties live in `world_properties` (owned by v-world) and are created
-- and priced from the admin panel -> Editor -> Properties.
Config = {}

Config.Distance = 2.0

-- Shells are base-game interiors, so nothing has to be streamed. `exit` is where a player
-- stands inside; the door they came through is remembered per session.
Config.Shells = {
    apartment = { x = 346.9,  y = -1012.9, z = -99.2,  h = 180.0 },
    motel     = { x = 152.2,  y = -1004.1, z = -99.0,  h = 340.0 },
    lowend    = { x = 265.8,  y = -1007.1, z = -101.0, h = 0.0 },
    modern    = { x = -786.9, y = 315.8,   z = 217.6,  h = 180.0 },
}

-- Buckets. Kept well clear of v-core's character-selection range (700000 + source), or
-- two systems would put players in the same private world by accident.
Config.BucketBase = 120000

Config.Blip = { sprite = 40, colour = 3, scale = 0.6 }

-- Rent. **A failed payment locks a property rather than deleting it**: deleting somebody's
-- stash because they were poor for a day is how a server loses a player. A locked property
-- can be paid off and reopened; a deleted one cannot.
Config.Rent = {
    intervalHours = 24,
    graceDays     = 3,      -- days of arrears before the door stops opening
}

-- What a motel is, as data.
Config.MotelDefaults = { slots = 15, garage = false, tenancy = 'rent' }

-- Real Los Santos addresses.
Config.Properties = {
    { id = 'motel_pinkcage_1', label = 'Pink Cage Motel, room 1', kind = 'motel', shell = 'motel',
      x = 322.0, y = -212.0, z = 54.2, h = 160.0, price = 0, rent = 250, tenancy = 'rent', slots = 15 },
    { id = 'motel_pinkcage_2', label = 'Pink Cage Motel, room 2', kind = 'motel', shell = 'motel',
      x = 326.4, y = -206.8, z = 54.2, h = 160.0, price = 0, rent = 250, tenancy = 'rent', slots = 15 },
    { id = 'apt_integrity_1',  label = 'Integrity Way, apt 28', kind = 'apartment', shell = 'apartment',
      x = -47.0, y = -585.6, z = 37.0, h = 340.0, price = 145000, rent = 0, tenancy = 'own', slots = 40 },
    { id = 'apt_delperro_1',   label = 'Del Perro Heights, apt 4', kind = 'apartment', shell = 'modern',
      x = -1447.0, y = -538.6, z = 34.7, h = 30.0, price = 220000, rent = 0, tenancy = 'own', slots = 50 },
    { id = 'house_mirror_1',   label = 'Mirror Park, 1 Nikola Ave', kind = 'house', shell = 'lowend',
      x = 1274.0, y = -574.0, z = 70.6, h = 65.0, price = 320000, rent = 0, tenancy = 'own',
      slots = 70, garage = true },
}
