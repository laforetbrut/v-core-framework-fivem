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
