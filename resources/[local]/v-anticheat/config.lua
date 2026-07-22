-- v-anticheat | shared config
-- The counterweight to everything else in this framework.
--
-- **The default action is LOG, not kick.** An anticheat that kicks legitimate players is
-- worse than no anticheat at all: it costs a server its population and it costs the
-- operator their trust in the tool. Every detector ships noisy-but-harmless, and an
-- operator raises the action once they have watched their own logs for a week.
Config = {}

-- What a flag does. 'log' | 'warn' (log + tell staff online) | 'kick' | 'ban'
Config.DefaultAction = 'log'

-- Staff above this tier are never flagged: noclip, teleports and spawned entities are
-- their job, and flagging them is pure noise.
Config.ExemptTier = 'mod'

Config.Detectors = {
    -- Distance covered between two samples, in metres per second. A jet does ~90 m/s, so
    -- the ceiling is well above anything legitimate on foot or in a vehicle.
    teleport = { enabled = true, sampleSeconds = 3, maxSpeed = 140.0, action = nil },

    -- Health above the engine maximum, or armour above 100.
    health   = { enabled = true, maxHealth = 200, maxArmour = 100, action = nil },

    -- Explosions nobody should be causing. The list is the ones with no legitimate source
    -- in a roleplay server; a grenade is fine, an orbital cannon is not.
    explosion = {
        enabled = true, perMinute = 6, action = nil,
        blocked = {
            [17] = true,  -- EXP_TAG_EXTINGUISHER
            [22] = true,  -- EXP_TAG_BIRD_CRAP
            [59] = true,  -- EXP_TAG_ORBITAL_CANNON
            [60] = true,  -- EXP_TAG_BOMB_STANDARD_WIDE
        },
    },

    -- Entities appearing faster than any legitimate flow. Garages, dealerships and the
    -- showroom all spawn through the server, so a client spawning at all is unusual.
    entity   = { enabled = true, perMinute = 12, action = nil },

    -- A money change with no reason attached, or one larger than any legitimate payout.
    money    = { enabled = true, maxDelta = 500000, action = nil },

    -- Damage dealt from further away than the weapon can reach.
    weapon   = { enabled = true, maxDistance = 250.0, action = nil },
}

-- How long a module's declared intent excuses a detector. Short on purpose: a grace window
-- is a hole, and a wide one is a wide hole.
Config.GraceSeconds = 8
