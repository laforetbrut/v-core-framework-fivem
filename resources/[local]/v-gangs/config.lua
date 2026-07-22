-- v-gangs | shared config
-- SEED DATA ONLY: gangs live in the `gangs` table and turfs in `world_turfs`, both owned
-- by v-world and both editable from the admin panel (Editor → Gangs / Turfs).
--
-- Membership, ranks and the treasury are NOT here: they are v-factions'. This module only
-- adds what is specific to the illegal side — territory.
Config = {}

-- Canonical Los Santos gangs. Grade 0 is the street rank, the top grade is the boss and
-- v-factions treats it as such unless an explicit `isboss` says otherwise.
Config.Gangs = {
    ballas = {
        label = 'Ballas', type = 'gang',
        grades = { [0] = { name = 'Soldier' }, [1] = { name = 'Enforcer' },
                   [2] = { name = 'Lieutenant' }, [3] = { name = 'Shot Caller' } },
    },
    vagos = {
        label = 'Vagos', type = 'gang',
        grades = { [0] = { name = 'Soldado' }, [1] = { name = 'Sicario' },
                   [2] = { name = 'Teniente' }, [3] = { name = 'Jefe' } },
    },
    families = {
        label = 'Families', type = 'gang',
        grades = { [0] = { name = 'Homie' }, [1] = { name = 'Hustler' },
                   [2] = { name = 'Lieutenant' }, [3] = { name = 'OG' } },
    },
    marabunta = {
        label = 'Marabunta Grande', type = 'gang',
        grades = { [0] = { name = 'Paro' }, [1] = { name = 'Homeboy' },
                   [2] = { name = 'Palabrero' }, [3] = { name = 'Ranflero' } },
    },
    lostmc = {
        label = 'The Lost MC', type = 'mafia',
        grades = { [0] = { name = 'Prospect' }, [1] = { name = 'Member' },
                   [2] = { name = 'Road Captain' }, [3] = { name = 'President' } },
    },
}

-- Territory. A turf is a circle: the capture rule only ever asks who is standing inside,
-- and a radius answers that with one distance check instead of a polygon test per tick.
Config.Turfs = {
    { id = 'grove',      label = 'Grove Street',        x = 106.0,   y = -1930.0, z = 21.3, radius = 110.0 },
    { id = 'forum',      label = 'Forum Drive',         x = -160.0,  y = -1610.0, z = 34.0, radius = 100.0 },
    { id = 'jamestown',  label = 'Jamestown Street',    x = 340.0,   y = -2050.0, z = 21.0, radius = 110.0 },
    { id = 'ranchoec',   label = 'Rancho El Burro',     x = 470.0,   y = -1750.0, z = 29.0, radius = 100.0 },
    { id = 'elrincon',   label = 'El Rincon Boulevard', x = 1120.0,  y = -1750.0, z = 36.0, radius = 100.0 },
    { id = 'chamberlain',label = 'Chamberlain Hills',   x = -120.0,  y = -1780.0, z = 30.0, radius = 110.0 },
    { id = 'sandy',      label = 'Sandy Shores',        x = 1960.0,  y = 3740.0,  z = 32.3, radius = 130.0 },
    { id = 'paleto',     label = 'Paleto Bay',          x = -140.0,  y = 6360.0,  z = 31.5, radius = 120.0 },
}

-- Capture. Influence is 0-100 and belongs to whoever holds it: a rival does not "take"
-- influence, they wear it down, and the turf only changes hands once it hits zero. That is
-- what makes a contested turf a fight rather than a race.
Config.Capture = {
    tick        = 20,    -- seconds between passes
    gainPerTick = 2.0,   -- for the owner (or a claimant on a free turf)
    lossPerTick = 3.0,   -- caused by a rival standing in it
    perExtra    = 0.5,   -- added per additional member beyond the first, per side
    maxMult     = 3.0,   -- a mob cannot capture instantly
    decayPerMin = 0.5,   -- influence lost when nobody is there: a turf must be held
    minToHold   = 5.0,   -- below this, the turf goes back to nobody
}

-- Blips. Colour is per gang so a map read tells you who runs what.
Config.Blip = { sprite = 84, alpha = 110, scale = 0.9 }
Config.GangColors = {
    ballas = 27, vagos = 44, families = 25, marabunta = 59, lostmc = 40,
}
Config.NeutralColor = 0
