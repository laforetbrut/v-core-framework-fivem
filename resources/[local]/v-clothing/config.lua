-- v-clothing | shared config
Config = {}

Config.Debug = false
Config.Distance = 2.2
Config.Blip = { sprite = 73, color = 25, scale = 0.7 }   -- 73 = clothing
Config.PedModel = 's_f_y_shop_mid'

-- Clothing stores (real GTA V brand locations).
Config.Locations = {
    { coords = vector4(-703.78, -152.26, 37.41, 120.0) },  -- Ponsonbys, Rockford Hills
    { coords = vector4(-1447.8, -242.5, 49.81, 40.0) },    -- Suburban, Del Perro
    { coords = vector4(75.6, -1392.4, 29.38, 268.0) },     -- Binco, Textile City
    { coords = vector4(425.6, -806.5, 29.49, 88.0) },      -- Suburban, Burton
    { coords = vector4(-1193.5, -768.9, 17.32, 214.0) },   -- Ponsonbys, Pillbox
}

-- Categories: kind = 'comp' (component) or 'prop' (prop). id = component/prop id.
Config.Categories = {
    { key = 'masks',      i18n = 'cl.masks',      kind = 'comp', id = 1,  price = 50,  item = 'mask' },
    { key = 'tops',       i18n = 'cl.tops',       kind = 'comp', id = 11, price = 150, item = 'top' },
    { key = 'undershirt', i18n = 'cl.undershirt', kind = 'comp', id = 8,  price = 40,  item = 'undershirt' },
    { key = 'arms',       i18n = 'cl.arms',       kind = 'comp', id = 3,  price = 30,  item = 'arms' },
    { key = 'pants',      i18n = 'cl.pants',      kind = 'comp', id = 4,  price = 120, item = 'pants' },
    { key = 'shoes',      i18n = 'cl.shoes',      kind = 'comp', id = 6,  price = 90,  item = 'shoes' },
    { key = 'hats',       i18n = 'cl.hats',       kind = 'prop', id = 0,  price = 70,  item = 'hat' },
    { key = 'glasses',    i18n = 'cl.glasses',    kind = 'prop', id = 1,  price = 55,  item = 'glasses' },
}

-- Component ids to reset when a piece is unequipped (nude / bare defaults).
Config.NudeDefaults = { [1] = 0, [11] = 15, [8] = 15, [3] = 15, [4] = 21, [6] = 34 }
