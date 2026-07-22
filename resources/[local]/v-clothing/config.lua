-- v-clothing | shared config
Config = {}

Config.Debug = false
Config.Distance = 2.2
Config.Blip = { sprite = 73, color = 25, scale = 0.7 }   -- 73 = clothing
Config.PedModel = 's_f_y_shop_mid'

-- ── SEED DATA ONLY ────────────────────────────────────────────────
-- Store locations and the wearable categories below are pushed to the DB once
-- (`world_clothing` / `clothing_categories`, owned by v-world) and then read back
-- from it. Everything is editable in-game from the admin panel → Editor; the tables
-- here are just what a fresh database starts with.

-- Clothing stores (real GTA V brand locations).
Config.Locations = {
    { label = 'Ponsonbys',  coords = vector4(-703.78, -152.26, 37.41, 120.0) },  -- Rockford Hills
    { label = 'Suburban',   coords = vector4(-1447.8, -242.5, 49.81, 40.0) },    -- Del Perro
    { label = 'Binco',      coords = vector4(75.6, -1392.4, 29.38, 268.0) },     -- Textile City
    { label = 'Suburban',   coords = vector4(425.6, -806.5, 29.49, 88.0) },      -- Burton
    { label = 'Ponsonbys',  coords = vector4(-1193.5, -768.9, 17.32, 214.0) },   -- Pillbox
    { label = 'Discount Store', coords = vector4(1196.1, 2710.2, 38.22, 178.0) },-- Route 68 / Harmony
    { label = 'Binco',      coords = vector4(-1108.4, 2708.9, 19.11, 222.0) },   -- Fort Zancudo road
    { label = 'Discount Store', coords = vector4(-3172.5, 1043.3, 20.86, 61.0) },-- Chumash
    { label = 'Binco',      coords = vector4(-821.3, -1073.9, 11.33, 128.0) },   -- Vespucci
    { label = 'Suburban',   coords = vector4(614.0, 2762.6, 42.09, 271.0) },  -- Paleto Bay
}

-- Categories = the wearable slots. kind = 'comp' (component) or 'prop' (prop).
-- `slot` is the GTA component/prop id. Several categories may share one slot on
-- purpose: gloves and bare arms are both component 3, and the ped can only render
-- one of them — which is exactly how gloves behave. Equipping one evicts the other.
-- framing = which camera preset the thumbnail scan uses.
Config.Categories = {
    -- Head
    { key = 'masks',      i18n = 'cl.masks',      kind = 'comp', id = 1,  price = 50,  item = 'mask',      framing = 'head',  sort = 10 },
    { key = 'hats',       i18n = 'cl.hats',       kind = 'prop', id = 0,  price = 70,  item = 'hat',       framing = 'head',  sort = 20 },
    { key = 'glasses',    i18n = 'cl.glasses',    kind = 'prop', id = 1,  price = 55,  item = 'glasses',   framing = 'head',  sort = 30 },
    { key = 'ears',       i18n = 'cl.ears',       kind = 'prop', id = 2,  price = 45,  item = 'earrings',  framing = 'head',  sort = 40 },
    -- Upper body
    { key = 'undershirt', i18n = 'cl.undershirt', kind = 'comp', id = 8,  price = 40,  item = 'undershirt', framing = 'upper', sort = 50 },
    { key = 'tops',       i18n = 'cl.tops',       kind = 'comp', id = 11, price = 150, item = 'top',       framing = 'upper', sort = 60 },
    { key = 'arms',       i18n = 'cl.arms',       kind = 'comp', id = 3,  price = 0,   item = 'arms',      framing = 'upper', sort = 70 },
    { key = 'gloves',     i18n = 'cl.gloves',     kind = 'comp', id = 3,  price = 60,  item = 'gloves',    framing = 'upper', sort = 80 },
    { key = 'vest',       i18n = 'cl.vest',       kind = 'comp', id = 9,  price = 250, item = 'vest',      framing = 'upper', sort = 90 },
    { key = 'decals',     i18n = 'cl.decals',     kind = 'comp', id = 10, price = 35,  item = 'decal',     framing = 'upper', sort = 100 },
    { key = 'chains',     i18n = 'cl.chains',     kind = 'comp', id = 7,  price = 180, item = 'chain',     framing = 'upper', sort = 110 },
    -- Accessories
    { key = 'bags',       i18n = 'cl.bags',       kind = 'comp', id = 5,  price = 110, item = 'bag',       framing = 'body',  sort = 120 },
    { key = 'watches',    i18n = 'cl.watches',    kind = 'prop', id = 6,  price = 200, item = 'watch_worn', framing = 'upper', sort = 130 },
    { key = 'bracelets',  i18n = 'cl.bracelets',  kind = 'prop', id = 7,  price = 90,  item = 'bracelet',  framing = 'upper', sort = 140 },
    -- Lower body
    { key = 'pants',      i18n = 'cl.pants',      kind = 'comp', id = 4,  price = 120, item = 'pants',     framing = 'lower', sort = 150 },
    { key = 'shoes',      i18n = 'cl.shoes',      kind = 'comp', id = 6,  price = 90,  item = 'shoes',     framing = 'lower', sort = 160 },
}

-- Component ids to reset when a piece is unequipped (nude / bare defaults).
Config.NudeDefaults = { [1] = 0, [11] = 15, [8] = 15, [3] = 15, [4] = 21, [6] = 34,
                        [5] = 0, [7] = 0, [9] = 0, [10] = 0 }

-- ── Thumbnail generation (admin panel → Tools → Clothing scan) ─────
-- Captures each drawable on the admin's ped via screenshot-basic and stores
-- the image so the catalogue shows a real preview instead of a number.
Config.Thumbs = {
    dir        = 'thumbs',   -- saved under the resource folder
    size       = 384,        -- final square thumbnail size (px), downscaled in the NUI
    format     = 'webp',     -- final format: 'webp' (small, alpha) | 'png' (alpha)
    quality    = 0.90,       -- final webp quality (0..1)
    streamWait = 160,        -- ms to let the drawable stream in before each shot
    permission = 'admin',    -- permission required to launch a scan
    maxBytes   = 300000,     -- server-side guard: reject uploads larger than this
    notifyEvery = 100,       -- toast progress every N thumbnails (NUI overlay is the primary UI)

    -- Garment isolation: each piece is shot twice (bare slot, then the piece)
    -- and the NUI keeps only the changed pixels -> transparent background,
    -- garment only (no character, no scenery). Disable to keep plain shots.
    isolate    = true,
    diffMin    = 30,         -- pixel delta (sum |dR|+|dG|+|dB|) where alpha starts
    diffMax    = 90,         -- pixel delta of full opacity (soft ramp between)
    pad        = 0.10,       -- crop padding around the garment (fraction of its size)

    -- "Studio": the admin is teleported to an isolated sky point (static
    -- background, no NPCs/wind/clouds, frozen noon) for the duration of the
    -- scan, then teleported back. Set to false to scan in place.
    studio     = vector3(0.0, -7000.0, 500.0),
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

-- Framing is per category now (`framing` field above, editable in the admin panel);
-- this is the fallback when a category names one that doesn't exist.
Config.DefaultFraming = 'body'
