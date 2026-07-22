-- v-drugs | shared config
-- SEED DATA ONLY: substances live in `world_drugs` (owned by v-world) and are edited from
-- the admin panel → Editor → Substances. One row carries both the growing side and the
-- street side, because an operator thinks in substances, not in subsystems.
--
-- What this module adds to the illegal loop that already shipped: the loop was static
-- (fixed gather nodes → craft → sell to a fixed buyer). This adds the parts that make it
-- a game: plantations a player places and can lose, and street dealing that pushes back.
Config = {}

Config.Distance = 2.0

-- Planting. A plant is a world object anyone can find, which is the whole tension: a good
-- spot is one nobody walks past.
Config.Plant = {
    prop        = 'prop_weed_01',
    maxPerPlayer = 6,
    minApart    = 8.0,     -- metres between two plants, so a field is not one pixel
    stealMult   = 0.5,     -- a thief gets this share of the yield
    stealSeconds = 12,     -- and it takes long enough to be caught doing it
}

-- Watering. Skip it and the plant wilts rather than dying outright: a wilted plant still
-- yields, just badly, so a bad grower is punished without being wiped.
Config.Water = { item = 'water', healthPerWater = 35, wiltPerHour = 20 }

-- Street dealing. Demand is per district and decays as you sell into it, so the same
-- corner stops paying and dealers have to move. That is the whole design.
Config.Street = {
    radius        = 18.0,   -- how close a ped has to be
    cooldown      = 20,     -- seconds between two offers
    demandFloor   = 0.35,   -- price never drops below this share of base
    demandDrop    = 0.06,   -- lost per sale in that district
    demandRecover = 0.02,   -- regained per minute
    turfBonus     = 0.25,   -- extra when dealing on your own gang's turf
    refuseAtHeat  = 70,     -- peds start refusing above this heat
}

-- Heat: the pressure side. It rises with every sale, decays when you stop, and drives
-- both refusals and the chance a sale is seen.
Config.Heat = {
    decayPerMin  = 1.5,
    max          = 100,
    bustBase     = 0.02,   -- chance per sale at zero heat
    bustAtMax    = 0.35,   -- chance per sale at maximum heat
    alertPolice  = true,   -- a bust puts a blip on the police map
    alertRadius  = 90.0,
}

-- Substances. `seed` = nil means the substance cannot be grown, only made or bought.
Config.Drugs = {
    { key = 'weed',    label = 'Cannabis', seed = 'weed_seed', product = 'cannabis',
      grow = 45, water = 2, min = 3, max = 6, price = 90,  heat = 3 },
    { key = 'coca',    label = 'Coca',     seed = 'coca_seed', product = 'cocaine',
      grow = 90, water = 3, min = 2, max = 4, price = 210, heat = 6 },
    -- Made in a lab rather than grown: no seed, but it still sells on the street.
    { key = 'meth',    label = 'Methamphetamine', seed = nil, product = 'meth_baggy',
      grow = 0,  water = 0, min = 0, max = 0, price = 260, heat = 8 },
}

-- Which item counts as sellable on the street for each substance is the `product` above.
-- Baggies sell better than raw material, so they get a multiplier.
Config.ProductMult = {
    weed_baggy = 1.6, weed_brick = 6.0,
    coke_baggy = 1.6, coke_brick = 6.0,
    meth_baggy = 1.0, meth_brick = 6.0,
}
