-- v-vehicleshop | shared config
-- Dealerships. The CATALOGUE is a v-world domain (`vehicle_catalogue`) like items and
-- recipes — a server operator adds a car from the admin panel, not from this file.
Config = {}

Config.Distance = 3.0
Config.Blip = { sprite = 523, color = 3, scale = 0.8 }
Config.Marker = { type = 21, size = 0.32, r = 255, g = 122, b = 26, a = 120 }

-- Test drive: a timed loan that returns you exactly where you started. The vehicle is a
-- LOCAL entity, so it never becomes an owned car and cannot be kept.
Config.TestDrive = { seconds = 60, cooldown = 120 }

-- What a dealership pays when you sell a car back to it, as a fraction of catalogue price.
-- Deliberately well under 1: a car is not a savings account.
Config.SellBackRate = 0.55

-- Categories a catalogue row can sit in (mirrors the GTA class families, kept short so the
-- shop tabs stay readable).
Config.Categories = {
    'compacts', 'sedans', 'suvs', 'coupes', 'muscle', 'sports', 'super',
    'motorcycles', 'offroad', 'vans', 'industrial', 'boats', 'air', 'utility',
}

-- SEED DATA ONLY — dealerships live in `world_dealers`, editable from the admin panel.
--   `cats` limits which categories this dealer sells (empty = everything)
Config.Dealers = {
    { id = 'pdm',      label = 'Premium Deluxe Motorsport', x = -33.8,   y = -1102.3, z = 26.4,
      sx = -20.2,  sy = -1088.6, sz = 26.7, sh = 68.0,  cats = 'compacts,sedans,suvs,coupes,muscle,sports,vans,offroad' },
    { id = 'luxury',   label = 'Luxury Autos',              x = -800.6,  y = -223.6,  z = 37.2,
      sx = -812.4, sy = -216.5,  sz = 36.9, sh = 118.0, cats = 'sports,super,coupes' },
    { id = 'bikes',    label = 'Motorcycle Dealer',         x = 296.4,   y = -1157.3, z = 29.3,
      sx = 285.6,  sy = -1147.9, sz = 29.3, sh = 178.0, cats = 'motorcycles' },
    { id = 'boats',    label = 'Boat Dealer',               x = -725.9,  y = -1315.4, z = 5.0,
      sx = -736.7, sy = -1332.5, sz = 0.2,  sh = 138.0, cats = 'boats' },
    { id = 'air',      label = 'Elitas Travel',             x = -1109.3, y = -2884.6, z = 13.9,
      sx = -1141.0,sy = -2870.0, sz = 13.9, sh = 330.0, cats = 'air' },
    { id = 'truckers', label = 'Truck & Utility Sales',     x = 1223.9,  y = 2727.5,  z = 38.0,
      sx = 1213.2, sy = 2735.6,  sz = 38.0, sh = 0.0,   cats = 'industrial,utility,vans' },
}

-- SEED DATA ONLY — the catalogue. Prices are deliberately spread so the economy has a
-- ladder rather than two tiers. `license` overrides what the class would otherwise need.
Config.Catalogue = {
    -- compacts
    { model = 'blista',     label = 'Dinka Blista',        cat = 'compacts', price = 16000 },
    { model = 'panto',      label = 'Benefactor Panto',    cat = 'compacts', price = 9500 },
    { model = 'issi2',      label = 'Weeny Issi',          cat = 'compacts', price = 14000 },
    { model = 'prairie',    label = 'Bollokan Prairie',    cat = 'compacts', price = 21000 },
    -- sedans
    { model = 'asea',       label = 'Declasse Asea',       cat = 'sedans', price = 12000 },
    { model = 'premier',    label = 'Declasse Premier',    cat = 'sedans', price = 24000 },
    { model = 'washington', label = 'Albany Washington',   cat = 'sedans', price = 32000 },
    { model = 'tailgater',  label = 'Obey Tailgater',      cat = 'sedans', price = 48000 },
    { model = 'schafter2',  label = 'Benefactor Schafter', cat = 'sedans', price = 62000 },
    -- SUVs
    { model = 'landstalker',label = 'Dundreary Landstalker', cat = 'suvs', price = 42000 },
    { model = 'cavalcade',  label = 'Albany Cavalcade',    cat = 'suvs', price = 55000 },
    { model = 'baller',     label = 'Gallivanter Baller',  cat = 'suvs', price = 78000 },
    { model = 'xls',        label = 'Benefactor XLS',      cat = 'suvs', price = 96000 },
    -- coupes
    { model = 'felon',      label = 'Lampadati Felon',     cat = 'coupes', price = 58000 },
    { model = 'exemplar',   label = 'Dewbauchee Exemplar', cat = 'coupes', price = 74000 },
    { model = 'windsor',    label = 'Enus Windsor',        cat = 'coupes', price = 145000 },
    -- muscle
    { model = 'blade',      label = 'Vapid Blade',         cat = 'muscle', price = 38000 },
    { model = 'dominator',  label = 'Vapid Dominator',     cat = 'muscle', price = 66000 },
    { model = 'gauntlet',   label = 'Bravado Gauntlet',    cat = 'muscle', price = 72000 },
    { model = 'sabregt',    label = 'Declasse Sabre GT',   cat = 'muscle', price = 61000 },
    -- sports
    { model = 'sultan',     label = 'Karin Sultan',        cat = 'sports', price = 68000 },
    { model = 'futo',       label = 'Karin Futo',          cat = 'sports', price = 44000 },
    { model = 'elegy2',     label = 'Annis Elegy RH8',     cat = 'sports', price = 92000 },
    { model = 'comet2',     label = 'Pfister Comet',       cat = 'sports', price = 148000 },
    { model = 'jester',     label = 'Dinka Jester',        cat = 'sports', price = 165000 },
    { model = 'banshee',    label = 'Bravado Banshee',     cat = 'sports', price = 132000 },
    -- super
    { model = 'zentorno',   label = 'Pegassi Zentorno',    cat = 'super', price = 725000 },
    { model = 't20',        label = 'Progen T20',          cat = 'super', price = 890000 },
    { model = 'adder',      label = 'Truffade Adder',      cat = 'super', price = 980000 },
    { model = 'osiris',     label = 'Pegassi Osiris',      cat = 'super', price = 810000 },
    -- electric (they exist in the catalogue so v-fuel's charging has customers)
    { model = 'dilettante', label = 'Karin Dilettante',    cat = 'compacts', price = 27000 },
    { model = 'voltic',     label = 'Coil Voltic',         cat = 'sports', price = 185000 },
    { model = 'raiden',     label = 'Coil Raiden',         cat = 'sports', price = 240000 },
    { model = 'cyclone',    label = 'Coil Cyclone',        cat = 'super', price = 690000 },
    -- motorcycles
    { model = 'bagger',     label = 'Western Bagger',      cat = 'motorcycles', price = 22000 },
    { model = 'akuma',      label = 'Dinka Akuma',         cat = 'motorcycles', price = 34000 },
    { model = 'bati',       label = 'Pegassi Bati 801',    cat = 'motorcycles', price = 48000 },
    { model = 'hakuchou',   label = 'Shitzu Hakuchou',     cat = 'motorcycles', price = 82000 },
    -- offroad
    { model = 'rebel2',     label = 'Karin Rebel',         cat = 'offroad', price = 28000 },
    { model = 'sandking',   label = 'Vapid Sandking XL',   cat = 'offroad', price = 64000 },
    { model = 'kamacho',    label = 'Canis Kamacho',       cat = 'offroad', price = 88000 },
    -- vans
    { model = 'burrito3',   label = 'Declasse Burrito',    cat = 'vans', price = 26000 },
    { model = 'youga',      label = 'Bravado Youga',       cat = 'vans', price = 24000 },
    { model = 'speedo',     label = 'Vapid Speedo',        cat = 'vans', price = 31000 },
    -- industrial / utility (need the HGV licence)
    { model = 'mule',       label = 'Maibatsu Mule',       cat = 'industrial', price = 72000 },
    { model = 'benson',     label = 'Vapid Benson',        cat = 'industrial', price = 94000 },
    { model = 'flatbed',    label = 'MTL Flatbed',         cat = 'industrial', price = 128000 },
    { model = 'towtruck',   label = 'Vapid Tow Truck',     cat = 'utility', price = 86000 },
    -- boats
    { model = 'dinghy',     label = 'Nagasaki Dinghy',     cat = 'boats', price = 42000 },
    { model = 'suntrap',    label = 'Shitzu Suntrap',      cat = 'boats', price = 68000 },
    { model = 'marquis',    label = 'Dinka Marquis',       cat = 'boats', price = 195000 },
    -- air
    { model = 'frogger',    label = 'Maibatsu Frogger',    cat = 'air', price = 1250000 },
    { model = 'buzzard2',   label = 'Nagasaki Buzzard',    cat = 'air', price = 1650000 },
    { model = 'dodo',       label = 'Mammoth Dodo',        cat = 'air', price = 780000 },
}

-- Which licence a category needs to be bought. A catalogue row can override it.
-- The server has no vehicle entity to read a GTA class from, and the category is the
-- human grouping a licence maps to anyway.
Config.CategoryLicense = {
    motorcycles = 'motorcycle',
    boats       = 'boat',
    air         = 'pilot',
    industrial  = 'truck',
    utility     = 'truck',
}
Config.DefaultLicense = 'driving'

-- Where a freshly bought car is parked. Must be a garage id v-garages knows.
Config.DefaultGarage = 'legion'
