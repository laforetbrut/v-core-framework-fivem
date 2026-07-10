-- v-appearance | shared config
Config = {}

Config.Debug = false

-- Freemode ped models per sex (0 male, 1 female).
Config.Models = { [0] = 'mp_m_freemode_01', [1] = 'mp_f_freemode_01' }

-- Head overlays we manage. id = SET_PED_HEAD_OVERLAY overlayID.
-- colorType: 1 = eyebrow/beard/chest hair palette, 2 = makeup/blush/lipstick palette.
-- The citizenfx doc lists makeup as colorType 1, but every mainstream open-source
-- appearance resource (illenium, qb) uses colorType 2 for the makeup-tint palette;
-- we follow community practice so the colour swatches match what players expect.
Config.Overlays = {
    blemishes   = { id = 0,  colorType = nil },
    beard       = { id = 1,  colorType = 1 },
    eyebrows    = { id = 2,  colorType = 1 },
    ageing      = { id = 3,  colorType = nil },
    makeup      = { id = 4,  colorType = 2 },
    blush       = { id = 5,  colorType = 2 },
    complexion  = { id = 6,  colorType = nil },
    sundamage   = { id = 7,  colorType = nil },
    lipstick    = { id = 8,  colorType = 2 },
    moles       = { id = 9,  colorType = nil },
    chesthair   = { id = 10, colorType = 1 },
    bodyblemish = { id = 11, colorType = nil },
}

-- Base-game collection is the empty string. NEVER 'mp_m_freemode_01' (that is a
-- ped model, not a collection name — passing it yields an invalid ref).
Config.BaseCollection = ''

-- Appearance schema version. Bump when the persisted shape changes.
Config.Schema = 2

-- Component ids that are clothing components (used by migration + validation).
Config.Components = { 1, 3, 4, 5, 6, 7, 8, 9, 10, 11 }   -- mask, arms, pants, bag, shoes, accessory, undershirt, armor, decal, top
Config.Props      = { 0, 1, 2, 6, 7 }                     -- hat, glasses, ears, watch, bracelet

-- Nude/bare defaults per component (used when a ref is invalid on this build).
Config.NudeDefaults = { [1] = 0, [11] = 15, [8] = 15, [3] = 15, [4] = 21, [6] = 34, [5] = 0, [7] = 0, [9] = 0, [10] = 0 }

-- Height (experimental, OFF by default — no GTA V native scales a ped; the
-- SET_ENTITY_MATRIX trick is visual only and glitches on vehicles/aiming/ragdoll).
Config.Height = {
    enabled = false,
    min     = 0.90,
    max     = 1.10,
}

-- ── Editor: barber / surgeon / tattooist stations ──────────────────
Config.Blip = { sprite = 71, color = 0, scale = 0.7 }   -- 71 = barber
Config.PedModel = 's_m_m_autoshop_01'
Config.Distance = 2.0

-- Each station opens the shared editor in a given mode.
Config.Stations = {
    barber  = {
        i18n = 'app.barber', ped = 's_f_y_hairdresser_01', blipSprite = 71,
        locations = {
            vector4(-814.31, -183.83, 37.57, 118.0),   -- Hair on Hawick
            vector4(136.82, -1708.34, 29.29, 138.0),    -- Davis
            vector4(-1282.6, -1116.8, 6.99, 128.0),      -- Vespucci
        },
    },
    surgery = {
        i18n = 'app.surgery', ped = 's_m_m_doctor_01', blipSprite = 61,
        locations = {
            vector4(-813.5, -184.6, 37.57, 118.0),       -- next to Hair on Hawick (plastic surgeon)
        },
    },
    tattoo  = {
        i18n = 'app.tattoo', ped = 's_m_y_tattoo_01', blipSprite = 75,
        locations = {
            vector4(322.15, 180.28, 103.59, 253.0),      -- Hawick tattoo parlour
            vector4(1322.66, -1651.9, 52.28, 300.0),     -- El Burro Heights
            vector4(-1153.6, -1425.7, 4.95, 124.0),      -- Vespucci
        },
    },
}

-- Head overlays exposed in the barber (style range from GET_PED_HEAD_OVERLAY_NUM,
-- opacity 0..1, colour where the overlay takes one). blush/makeup/lipstick were
-- previously dead (no blush overlay, opacity hard-0) — fixed here + in the engine.
Config.BarberOverlays = { 'eyebrows', 'beard', 'chesthair', 'makeup', 'blush', 'lipstick', 'ageing', 'complexion', 'moles', 'blemishes' }

-- Face features exposed in the surgeon (SET_PED_FACE_FEATURE index -> label key).
Config.FaceFeatures = {
    { id = 0,  i18n = 'app.ff.nose_width' },
    { id = 1,  i18n = 'app.ff.nose_height' },
    { id = 2,  i18n = 'app.ff.nose_length' },
    { id = 3,  i18n = 'app.ff.nose_bridge' },
    { id = 4,  i18n = 'app.ff.nose_tip' },
    { id = 5,  i18n = 'app.ff.nose_shift' },
    { id = 6,  i18n = 'app.ff.brow_height' },
    { id = 7,  i18n = 'app.ff.brow_depth' },
    { id = 8,  i18n = 'app.ff.cheek_height' },
    { id = 9,  i18n = 'app.ff.cheek_width' },
    { id = 10, i18n = 'app.ff.cheek_puff' },
    { id = 11, i18n = 'app.ff.eyes' },
    { id = 12, i18n = 'app.ff.lips' },
    { id = 13, i18n = 'app.ff.jaw_width' },
    { id = 14, i18n = 'app.ff.jaw_length' },
    { id = 15, i18n = 'app.ff.chin_lower' },
    { id = 16, i18n = 'app.ff.chin_length' },
    { id = 17, i18n = 'app.ff.chin_width' },
    { id = 18, i18n = 'app.ff.chin_hole' },
    { id = 19, i18n = 'app.ff.neck' },
}
