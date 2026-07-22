-- v-crafting | shared config
-- Workbenches turn raw items into finished ones. Stations and recipes live here
-- so both client (markers / prompts) and server (proximity + authority) share them.
Config = {}

Config.Debug = false

-- Interaction distance to a bench, and the marker drawn on the ground.
Config.Distance = 1.8
Config.Marker   = { type = 21, size = 0.9, r = 255, g = 106, b = 26, a = 120 }

-- Minimum seconds between two crafts from the same player (anti-spam; the client
-- also plays a progress bar of `recipe.time`, but the server is the authority).
Config.Cooldown = 1

-- ── Stations ───────────────────────────────────────────────────
-- Each station has an id, a label, a map blip and a list of world benches.
-- A recipe is shown at a station when its `station` field matches the id.
Config.Stations = {
    workbench = {
        label = 'Workbench',
        blip  = { sprite = 566, color = 47, scale = 0.7 },
        benches = {
            vector4(-337.02, -136.28, 39.01, 70.0),   -- Los Santos Customs (Burton)
            vector4(1273.06, -1719.6, 54.77, 300.0),  -- El Burro Heights lot
        },
    },
    ammo = {
        label = 'Reloading Bench',
        blip  = { sprite = 110, color = 1, scale = 0.7 },
        benches = {
            vector4(21.86, -1108.18, 29.8, 160.0),     -- Ammu-Nation (Innocence Blvd)
            vector4(810.2, -2157.4, 29.62, 356.0),     -- Cypress Flats warehouse
        },
    },
    cooking = {
        label = 'Kitchen',
        blip  = { sprite = 267, color = 2, scale = 0.7 },
        benches = {
            vector4(1.9, -1288.55, 29.03, 300.0),      -- Diner (Strawberry)
            vector4(-1197.34, -892.05, 13.99, 125.0),  -- Del Perro pier stand
        },
    },
    electronics = {
        label = 'Electronics Bench',
        blip  = { sprite = 606, color = 3, scale = 0.7 },
        benches = {
            vector4(707.03, -965.4, 30.41, 90.0),      -- Mission Row workshop
        },
    },
    recycler = {
        label = 'Recycling Center',
        blip  = { sprite = 365, color = 5, scale = 0.7 },
        benches = {
            vector4(1057.3, -2313.6, 30.6, 90.0),      -- Cypress Flats scrap yard
            vector4(-322.9, -1546.6, 26.9, 180.0),     -- El Burro industrial (recycling)
        },
    },
    druglab = {
        label = 'Processing',
        blip  = false,                                 -- illegal: hidden, no map blip
        benches = {
            vector4(1391.5, 3608.5, 38.9, 200.0),      -- Sandy Shores trailer
            vector4(-1170.5, -1571.9, 4.4, 30.0),      -- Del Perro beach lockup
        },
    },
}

-- ── Recipes ────────────────────────────────────────────────────
-- output   : produced item name (must exist in the `items` table)
-- count    : units produced per craft
-- time      : client progress-bar duration (ms)
-- station  : which station shows this recipe
-- inputs   : { itemName = qtyPerCraft, ... } consumed from the inventory
-- gate     : optional { job=, grade=, permission= } to restrict who can craft it
Config.Recipes = {
    -- Workbench: tools & basic materials
    { output = 'lockpick',          count = 1, time = 3500, station = 'workbench',   inputs = { metal_scrap = 2, plastic = 1 } },
    { output = 'advanced_lockpick', count = 1, time = 6000, station = 'workbench',   inputs = { lockpick = 1, electronics = 1, metal_scrap = 2 } },
    { output = 'screwdriver_set',   count = 1, time = 4000, station = 'workbench',   inputs = { metal_scrap = 2, plastic = 2 } },
    { output = 'cable',             count = 2, time = 2500, station = 'workbench',   inputs = { copper = 2, rubber = 1 } },
    { output = 'rope',              count = 1, time = 3000, station = 'workbench',   inputs = { cloth = 2, cotton = 2 } },
    { output = 'nails',             count = 5, time = 2000, station = 'workbench',   inputs = { iron = 1 } },
    { output = 'repair_kit',        count = 1, time = 7000, station = 'workbench',   inputs = { metal_scrap = 3, duct_tape = 1, cable = 1 } },
    { output = 'drill',             count = 1, time = 8000, station = 'workbench',   inputs = { electronics = 1, metal_scrap = 3, lithium_battery = 1 } },
    { output = 'cleaning_kit',      count = 1, time = 3000, station = 'workbench',   inputs = { cloth = 2, rubber = 1, plastic = 1 } },

    -- Reloading bench: ammunition
    { output = 'ammo_9mm',          count = 1, time = 3000, station = 'ammo',        inputs = { gunpowder = 2, brass = 1, copper = 1 } },
    { output = 'ammo_762',          count = 1, time = 4000, station = 'ammo',        inputs = { gunpowder = 3, brass = 2, copper = 1 } },
    { output = 'ammo_44',           count = 1, time = 3500, station = 'ammo',        inputs = { gunpowder = 3, brass = 2 } },
    { output = 'ammo_shotgun',      count = 1, time = 3500, station = 'ammo',        inputs = { gunpowder = 2, plastic = 1, brass = 1 } },
    { output = 'attach_suppressor', count = 1, time = 9000, station = 'ammo',        inputs = { metal_scrap = 3, rubber = 2, aluminum = 1 } },
    { output = 'attach_flashlight', count = 1, time = 6000, station = 'ammo',        inputs = { electronics = 1, plastic = 2, battery_9v = 1 } },
    { output = 'attach_scope',      count = 1, time = 8000, station = 'ammo',        inputs = { glass = 2, aluminum = 2, electronics = 1 } },
    { output = 'attach_grip',       count = 1, time = 5000, station = 'ammo',        inputs = { plastic = 3, aluminum = 1 } },
    { output = 'attach_extclip',    count = 1, time = 6000, station = 'ammo',        inputs = { metal_scrap = 2, brass = 2 } },

    -- Kitchen: food
    { output = 'dough',             count = 1, time = 2500, station = 'cooking',     inputs = { flour = 2, eggs = 1, milk = 1 } },
    { output = 'bagel',             count = 2, time = 3000, station = 'cooking',     inputs = { dough = 1 } },
    { output = 'bacon_eggs',        count = 1, time = 3500, station = 'cooking',     inputs = { bacon = 1, eggs = 2 } },
    { output = 'boiled_meat',       count = 1, time = 3000, station = 'cooking',     inputs = { meat = 1 } },
    { output = 'bacon_cheeseburger',count = 1, time = 4500, station = 'cooking',     inputs = { bread = 2, bacon = 2, cheese = 1 } },
    { output = 'brownie',           count = 2, time = 4000, station = 'cooking',     inputs = { flour = 1, sugar = 1, butter = 1, eggs = 1 } },
    { output = 'blueberry_pie',     count = 1, time = 5000, station = 'cooking',     inputs = { dough = 1, blueberries = 2, sugar = 1 } },

    -- Electronics bench: tech
    { output = 'electronics',       count = 1, time = 3000, station = 'electronics', inputs = { copper = 2, plastic = 1, cable = 1 } },
    { output = 'lithium_battery',   count = 1, time = 3500, station = 'electronics', inputs = { metal_scrap = 1, copper = 1, aluminum = 1 } },
    { output = 'radio',             count = 1, time = 5000, station = 'electronics', inputs = { electronics = 2, plastic = 1, battery_9v = 1 } },
    { output = 'lock_breaker',      count = 1, time = 6000, station = 'electronics', inputs = { electronics = 2, metal_scrap = 1, lithium_battery = 1 } },
    { output = 'hacking_device',    count = 1, time = 9000, station = 'electronics', inputs = { electronics = 3, usb_drive = 1, cable = 2 } },
    { output = 'phone',             count = 1, time = 8000, station = 'electronics', inputs = { electronics = 2, glass = 1, plastic = 1, lithium_battery = 1 } },

    -- Recycling: break finished items back into a fraction of their materials (always a
    -- net loss vs crafting, so it can't be farmed in a loop).
    { output = 'metal_scrap',       count = 1, time = 2500, station = 'recycler',    inputs = { lockpick = 1 } },
    { output = 'metal_scrap',       count = 2, time = 3500, station = 'recycler',    inputs = { advanced_lockpick = 1 } },
    { output = 'metal_scrap',       count = 2, time = 3500, station = 'recycler',    inputs = { screwdriver_set = 1 } },
    { output = 'metal_scrap',       count = 2, time = 4000, station = 'recycler',    inputs = { drill = 1 } },
    { output = 'copper',            count = 1, time = 2500, station = 'recycler',    inputs = { cable = 2 } },
    { output = 'copper',            count = 1, time = 3000, station = 'recycler',    inputs = { electronics = 1 } },
    { output = 'electronics',       count = 1, time = 4000, station = 'recycler',    inputs = { radio = 1 } },
    { output = 'electronics',       count = 1, time = 4500, station = 'recycler',    inputs = { phone = 1 } },
    { output = 'cloth',             count = 1, time = 2500, station = 'recycler',    inputs = { rope = 1 } },
    -- Refining: upgrade raw stock into a higher-tier material.
    { output = 'iron',              count = 1, time = 4000, station = 'recycler',    inputs = { metal_scrap = 3 } },
    { output = 'cloth',             count = 1, time = 3000, station = 'recycler',    inputs = { cotton = 2 } },

    -- Illegal processing: package raw product into sellable street units.
    { output = 'joint',             count = 1, time = 2500, station = 'druglab',     inputs = { cannabis = 1, rolling_paper = 1 } },
    { output = 'blunt',             count = 1, time = 3000, station = 'druglab',     inputs = { cannabis = 2 } },
    { output = 'weed_baggy',        count = 1, time = 3500, station = 'druglab',     inputs = { cannabis = 3 } },
    { output = 'weed_brick',        count = 1, time = 8000, station = 'druglab',     inputs = { weed_baggy = 10 } },
    { output = 'coke_baggy',        count = 12, time = 6000, station = 'druglab',    inputs = { coke_brick = 1 } },
    { output = 'crack_baggy',       count = 1, time = 4000, station = 'druglab',     inputs = { coke_baggy = 1, baking_soda = 1 } },
    { output = 'meth_baggy',        count = 12, time = 6000, station = 'druglab',    inputs = { meth_brick = 1 } },

    -- ── Extended catalogue ──────────────────────────────────────────────────
    -- Reaches the items added to the catalogue so nothing in it is unobtainable.
    -- Seed data only: everything below is editable in-game (v-admin → Editor → Craft).

    -- Refining the new material tier
    { output = 'steel',             count = 1, time = 5000, station = 'recycler',    inputs = { iron = 2, metal_scrap = 2 } },
    { output = 'aluminum_sheet',    count = 2, time = 3500, station = 'recycler',    inputs = { aluminum = 2 } },
    { output = 'titanium',          count = 1, time = 9000, station = 'recycler',    inputs = { steel = 3, aluminum = 2 } },
    { output = 'carbon_fiber',      count = 1, time = 7000, station = 'recycler',    inputs = { plastic = 4, resin = 1 } },
    { output = 'leather',           count = 1, time = 4000, station = 'recycler',    inputs = { cloth = 3 } },
    { output = 'wire',              count = 2, time = 2500, station = 'workbench',   inputs = { copper = 2 } },
    { output = 'screws',            count = 6, time = 2000, station = 'workbench',   inputs = { steel = 1 } },
    { output = 'spring',            count = 2, time = 2500, station = 'workbench',   inputs = { steel = 1, wire = 1 } },
    { output = 'resin',             count = 2, time = 3000, station = 'workbench',   inputs = { plastic = 2, rubber = 1 } },
    { output = 'kevlar',            count = 1, time = 8000, station = 'workbench',   inputs = { cloth = 4, resin = 2 } },

    -- Hand tools
    { output = 'hammer',            count = 1, time = 3500, station = 'workbench',   inputs = { steel = 1, wood = 1 } },
    { output = 'wrench_tool',       count = 1, time = 3500, station = 'workbench',   inputs = { steel = 2 } },
    { output = 'pliers',            count = 1, time = 3000, station = 'workbench',   inputs = { steel = 1, spring = 1, rubber = 1 } },
    { output = 'crowbar_tool',      count = 1, time = 4500, station = 'workbench',   inputs = { steel = 3 } },
    { output = 'handsaw',           count = 1, time = 4000, station = 'workbench',   inputs = { steel = 2, wood = 1 } },
    { output = 'chisel',            count = 1, time = 2500, station = 'workbench',   inputs = { steel = 1 } },
    { output = 'multitool',         count = 1, time = 6000, station = 'workbench',   inputs = { steel = 2, spring = 2, screws = 4 } },
    { output = 'welding_torch',     count = 1, time = 9000, station = 'workbench',   inputs = { steel = 3, rubber = 2, copper = 2 } },
    { output = 'angle_grinder',     count = 1, time = 9000, station = 'workbench',   inputs = { steel = 3, electronics = 1, lithium_battery = 1 } },
    { output = 'toolbox',           count = 1, time = 10000, station = 'workbench',  inputs = { hammer = 1, wrench_tool = 1, pliers = 1, screws = 6 } },
    { output = 'zip_ties',          count = 5, time = 2000, station = 'workbench',   inputs = { plastic = 2 } },
    { output = 'handcuffs',         count = 1, time = 5000, station = 'workbench',   inputs = { steel = 2, spring = 1, screws = 2 } },
    { output = 'flashlight',        count = 1, time = 3500, station = 'workbench',   inputs = { aluminum_sheet = 1, battery_9v = 1, glass = 1 } },
    { output = 'fishing_rod',       count = 1, time = 5000, station = 'workbench',   inputs = { carbon_fiber = 1, wire = 2, spring = 1 } },
    { output = 'pickaxe',           count = 1, time = 6000, station = 'workbench',   inputs = { steel = 3, wood = 1 } },
    { output = 'axe',               count = 1, time = 5500, station = 'workbench',   inputs = { steel = 2, wood = 1 } },
    { output = 'shovel_spade',      count = 1, time = 5000, station = 'workbench',   inputs = { steel = 2, wood = 1 } },

    -- Field medicine
    { output = 'gauze',             count = 3, time = 2000, station = 'cooking',     inputs = { cloth = 1 } },
    { output = 'tourniquet',        count = 1, time = 2500, station = 'workbench',   inputs = { cloth = 1, rubber = 1 } },
    { output = 'splint',            count = 1, time = 3000, station = 'workbench',   inputs = { wood = 1, cloth = 2 } },
    { output = 'suture_kit',        count = 1, time = 4000, station = 'workbench',   inputs = { wire = 1, cloth = 1, gauze = 1 } },

    -- Electronics bench: the new tech tier
    { output = 'motherboard',       count = 1, time = 7000, station = 'electronics', inputs = { electronics = 2, copper = 2, wire = 2 } },
    { output = 'cpu_chip',          count = 1, time = 9000, station = 'electronics', inputs = { electronics = 3, copper = 1 } },
    { output = 'gpu_card',          count = 1, time = 12000, station = 'electronics',inputs = { motherboard = 1, cpu_chip = 1, aluminum_sheet = 1 } },
    { output = 'hard_drive',        count = 1, time = 6000, station = 'electronics', inputs = { electronics = 1, aluminum_sheet = 1, magnet = 1 } },
    { output = 'magnet',            count = 1, time = 4000, station = 'electronics', inputs = { iron = 2, copper = 1 } },
    { output = 'antenna',           count = 1, time = 3500, station = 'electronics', inputs = { aluminum_sheet = 1, wire = 2 } },
    { output = 'tablet',            count = 1, time = 11000, station = 'electronics',inputs = { motherboard = 1, glass = 2, lithium_battery = 1, plastic = 2 } },
    { output = 'gps_unit',          count = 1, time = 7000, station = 'electronics', inputs = { electronics = 2, antenna = 1, glass = 1 } },
    { output = 'micro_bug',         count = 1, time = 8000, station = 'electronics', inputs = { electronics = 1, wire = 1, battery_9v = 1 } },
    { output = 'signal_scanner',    count = 1, time = 11000, station = 'electronics',inputs = { electronics = 3, antenna = 2, lithium_battery = 1 } },
    { output = 'signal_jammer',     count = 1, time = 15000, station = 'electronics',inputs = { signal_scanner = 1, antenna = 2, lithium_battery = 2 } },

    -- Kitchen: the expanded menu
    { output = 'sandwich',          count = 1, time = 2500, station = 'cooking',     inputs = { bread = 1, cheese = 1, bacon = 1 } },
    { output = 'hotdog',            count = 1, time = 2500, station = 'cooking',     inputs = { bread = 1, meat = 1 } },
    { output = 'taco',              count = 2, time = 3000, station = 'cooking',     inputs = { dough = 1, meat = 1, cheese = 1 } },
    { output = 'burrito',           count = 1, time = 3500, station = 'cooking',     inputs = { dough = 1, meat = 2, cheese = 1 } },
    { output = 'pizza_slice',       count = 4, time = 5000, station = 'cooking',     inputs = { dough = 2, cheese = 2 } },
    { output = 'fries',             count = 2, time = 2500, station = 'cooking',     inputs = { potato = 2, butter = 1 } },
    { output = 'soup',              count = 2, time = 3500, station = 'cooking',     inputs = { meat = 1, water = 2 } },
    { output = 'steak',             count = 1, time = 4000, station = 'cooking',     inputs = { meat = 2, butter = 1 } },
    { output = 'pancakes',          count = 2, time = 3500, station = 'cooking',     inputs = { flour = 2, eggs = 2, milk = 1 } },
    { output = 'ice_cream',         count = 2, time = 3000, station = 'cooking',     inputs = { milk = 2, sugar = 1 } },
    { output = 'milkshake',         count = 1, time = 2500, station = 'cooking',     inputs = { milk = 2, ice_cream = 1 } },
    { output = 'lemonade',          count = 2, time = 2500, station = 'cooking',     inputs = { water = 2, sugar = 1, lemon = 1 } },
    { output = 'iced_tea',          count = 2, time = 2500, station = 'cooking',     inputs = { water = 2, sugar = 1 } },
    { output = 'fish_fillet',       count = 1, time = 2500, station = 'cooking',     inputs = { fish = 1 } },
}
