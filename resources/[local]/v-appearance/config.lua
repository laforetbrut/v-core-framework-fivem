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
