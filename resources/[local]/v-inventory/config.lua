-- v-inventory | shared config
Config = {}

Config.Debug = false

-- Personal inventory (realistic: 30 kg carry limit).
Config.MaxWeight = 30000      -- grams (30 kg)
Config.MaxSlots  = 40

-- Vehicle storage (capacity scales a little with vehicle class server-side).
Config.Trunk    = { slots = 45, weight = 250000 }
Config.Glovebox = { slots = 5,  weight = 12000 }

-- Ground drops.
Config.Drop     = { slots = 30, weight = 1000000 }

-- Hidden pocket: a small concealed compartment on the player. Stored in the
-- character's metadata (separate from the main inventory), so a police search —
-- which reads GetSearchable / GetItems (the main inventory only) — never sees it.
Config.Pocket   = { slots = 3, weight = 1000 }   -- 1 kg

-- Carrying a backpack item raises the personal carry capacity by this much.
Config.Backpack = { slots = 12, weight = 20000 }   -- +12 slots, +20 kg

-- Body-armor items apply this much armour on use (0..100).
Config.ArmorAmount = 100

-- Rounds granted per ammo item used (added to the equipped weapon).
Config.AmmoPerItem = 30

-- Shared / gang stashes: a persistent container gated by job, gang or permission.
-- Open one with exports['v-inventory']:OpenSharedStash(src, id) (e.g. from a
-- target zone or a job menu). Access is checked server-side on every open.
--   job=<name> (+ minGrade), gang=<name>, or permission=<tier>.
Config.SharedStashes = {
    -- ['police_armory'] = { label = 'Armurerie LSPD', slots = 60, weight = 500000, job = 'police', minGrade = 0 },
    -- ['gang_lost']     = { label = 'Planque',        slots = 50, weight = 400000, gang = 'lost' },
    -- ['admin_store']   = { label = 'Dépôt Admin',    slots = 80, weight = 999999, permission = 'admin' },
}

-- Giving items to a nearby player.
Config.GiveDistance = 3.0

-- Give distance already above. Hotbar = first N player slots.
Config.HotbarSlots = 5

-- Category → accent colour used on the slot's left edge (on-theme, muted).
Config.Categories = {
    money       = '#43C46A',
    general     = '#FF9354',
    food        = '#43C46A',
    drinks      = '#4AA8FF',
    medical     = '#E5484D',
    weapons     = '#9C99A2',
    tools       = '#F5A623',
    materials   = '#B0895E',
    ingredients = '#7FB86B',
    drugs       = '#C77DFF',
    smokes      = '#8C8C8C',
    tech        = '#4AA8FF',
    jewelry     = '#F5C542',
    mechanic    = '#F5A623',
    misc        = '#FF6A1A',
}
