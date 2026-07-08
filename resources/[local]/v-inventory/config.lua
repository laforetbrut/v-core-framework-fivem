-- v-inventory | shared config
Config = {}

Config.Debug = false

-- Personal inventory.
Config.MaxWeight = 120000     -- grams (120 kg)
Config.MaxSlots  = 40

-- Vehicle storage (capacity scales a little with vehicle class server-side).
Config.Trunk    = { slots = 45, weight = 250000 }
Config.Glovebox = { slots = 5,  weight = 12000 }

-- Ground drops.
Config.Drop     = { slots = 30, weight = 1000000 }

-- Giving items to a nearby player.
Config.GiveDistance = 3.0

-- Category → accent colour used in the grid (kept on-theme, no rainbow).
Config.Categories = {
    food    = '#43C46A',
    medical = '#E5484D',
    weapon  = '#9C99A2',
    tool    = '#F5A623',
    gadget  = '#4AA8FF',
    money   = '#43C46A',
    misc    = '#FF6A1A',
}
