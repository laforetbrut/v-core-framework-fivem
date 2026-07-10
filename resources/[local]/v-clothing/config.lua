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

-- ── Thumbnail generation (admin scan: /scanclothes) ────────────────
-- Captures each drawable on the admin's ped via screenshot-basic and stores
-- the image so the catalogue shows a real preview instead of a number.
Config.Thumbs = {
    dir        = 'thumbs',   -- saved under the resource folder
    encoding   = 'jpg',      -- 'jpg' (small) | 'png' | 'webp'
    quality    = 0.80,       -- 0..1 for jpg/webp
    streamWait = 160,        -- ms to let the drawable stream in before the shot
    permission = 'admin',    -- permission required to run /scanclothes
    maxBytes   = 900000,     -- server-side guard: reject blobs larger than this
    notifyEvery = 20,        -- push a progress notification every N thumbnails
}

-- Camera framing per body zone. bone = ped bone to look at (skeleton tag,
-- pose-independent), dist = camera distance in front, height = camera Z offset,
-- atZ = look-at Z offset, fov = field of view. Tune in-game if needed.
Config.Framing = {
    head  = { bone = 31086, dist = 0.85, height = 0.03, atZ = 0.00, fov = 25.0 },  -- SKEL_Head
    upper = { bone = 24818, dist = 1.45, height = 0.05, atZ = 0.00, fov = 32.0 },  -- SKEL_Spine3
    lower = { bone = 11816, dist = 1.55, height = 0.00, atZ = -0.05, fov = 38.0 }, -- SKEL_Pelvis
    body  = { bone = 24818, dist = 2.20, height = 0.00, atZ = -0.30, fov = 42.0 }, -- full body
}

-- Which framing each category uses when generating thumbnails.
Config.CatFraming = {
    masks = 'head',  tops = 'upper', undershirt = 'upper', arms = 'upper',
    pants = 'lower', shoes = 'lower', hats = 'head',       glasses = 'head',
}
