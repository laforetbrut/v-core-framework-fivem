-- v-police | shared config
-- SEED DATA ONLY: the penal code lives in `world_charges` (owned by v-world) and is
-- editable from the admin panel → Editor → Charges. Everything a server actually wants to
-- tune — fines, jail time, licence points — is data, because every server rewrites its
-- charge sheet first.
Config = {}

-- Which jobs count as law enforcement. A job, not a permission: staff are not police.
Config.Jobs = { police = true, sheriff = true }

-- Keybind for the officer panel. Rebindable by the player in the FiveM settings.
Config.Key = 'F5'

-- Interaction range for cuffing, searching and escorting.
Config.Distance = 2.5

-- Cuffing takes an item, so an officer can be disarmed of the ability. Set to false to
-- drop the requirement.
Config.CuffItem = 'handcuffs'

-- Bolingbroke Penitentiary — the canonical Los Santos prison.
Config.Jail = {
    x = 1691.0, y = 2565.0, z = 45.6, heading = 190.0,
    release = { x = 1846.0, y = 2585.0, z = 45.7, heading = 275.0 },
    maxMinutes = 120,
}

-- Escort: how far behind the officer the detainee is attached.
Config.Escort = { bone = 11816, x = 0.32, y = 0.45, z = 0.0 }

Config.BlipJail = { sprite = 188, colour = 40, label = 'Bolingbroke Penitentiary' }

-- The starting penal code. Codes are the server's own; these mirror common Los Santos
-- roleplay usage rather than any real jurisdiction.
Config.Charges = {
    -- traffic
    { code = 'T01', label = 'Speeding',                        cat = 'traffic', fine = 350,  jail = 0,  points = 2, license = 'driver' },
    { code = 'T02', label = 'Reckless driving',                cat = 'traffic', fine = 900,  jail = 5,  points = 4, license = 'driver' },
    { code = 'T03', label = 'Driving without a licence',       cat = 'traffic', fine = 750,  jail = 0 },
    { code = 'T04', label = 'Hit and run',                     cat = 'traffic', fine = 1500, jail = 10, points = 6, license = 'driver' },
    { code = 'T05', label = 'Driving under the influence',     cat = 'traffic', fine = 2000, jail = 15, points = 8, license = 'driver' },
    -- misdemeanour
    { code = 'M01', label = 'Disorderly conduct',              cat = 'misdemeanour', fine = 400,  jail = 0 },
    { code = 'M02', label = 'Trespassing',                     cat = 'misdemeanour', fine = 600,  jail = 5 },
    { code = 'M03', label = 'Petty theft',                     cat = 'misdemeanour', fine = 800,  jail = 10 },
    { code = 'M04', label = 'Obstruction of justice',          cat = 'misdemeanour', fine = 1200, jail = 10 },
    { code = 'M05', label = 'Evading a peace officer',         cat = 'misdemeanour', fine = 1500, jail = 15 },
    -- felony
    { code = 'F01', label = 'Grand theft auto',                cat = 'felony', fine = 3000,  jail = 25 },
    { code = 'F02', label = 'Assault',                         cat = 'felony', fine = 2500,  jail = 20 },
    { code = 'F03', label = 'Armed robbery',                   cat = 'felony', fine = 6000,  jail = 40 },
    { code = 'F04', label = 'Kidnapping',                      cat = 'felony', fine = 7000,  jail = 45 },
    { code = 'F05', label = 'Attempted murder',                cat = 'felony', fine = 10000, jail = 60 },
    { code = 'F06', label = 'Murder',                          cat = 'felony', fine = 15000, jail = 90 },
    -- weapons
    { code = 'W01', label = 'Carrying without a permit',       cat = 'weapons', fine = 2500, jail = 20 },
    { code = 'W02', label = 'Illegal firearm',                 cat = 'weapons', fine = 5000, jail = 35 },
    -- drugs
    { code = 'D01', label = 'Possession of a controlled substance', cat = 'drugs', fine = 1500, jail = 15 },
    { code = 'D02', label = 'Possession with intent to supply',     cat = 'drugs', fine = 4000, jail = 35 },
    { code = 'D03', label = 'Manufacture of narcotics',             cat = 'drugs', fine = 8000, jail = 60 },
}
