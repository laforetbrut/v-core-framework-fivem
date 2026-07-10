-- v-gathering | shared config
-- Resource nodes let players harvest the raw materials that v-crafting consumes,
-- closing the economy loop: gather -> craft -> use / sell. Node coords live here so
-- both client (markers / prompts) and server (proximity authority) share them.
Config = {}

Config.Debug = false

Config.Distance = 1.8
Config.Marker   = { type = 1, size = 1.2, r = 255, g = 106, b = 26, a = 90 }

-- Absolute floor (seconds) between two harvests. The real pace is each resource's own
-- `time` (enforced server-side), so this is just a safety minimum on top of it.
Config.Cooldown = 2

-- ── Resource types ─────────────────────────────────────────────
-- label   : shown on the blip / prompt
-- time     : harvest duration (ms) — the scenario plays for this long
-- scenario : GTA world scenario played while harvesting
-- blip     : { sprite, color, scale }
-- yields   : weighted table; each harvest picks ONE by weight, amount = random(min,max)
-- rare      : optional { item, chance } bonus rolled on top
Config.Resources = {
    mining = {
        label = 'Mining Site', time = 4500, scenario = 'WORLD_HUMAN_HAMMERING',
        blip = { sprite = 618, color = 21, scale = 0.7 },
        yields = {
            { item = 'metal_scrap', min = 1, max = 3, weight = 60 },
            { item = 'iron',        min = 1, max = 2, weight = 45 },
            { item = 'copper',      min = 1, max = 2, weight = 35 },
            { item = 'aluminum',    min = 1, max = 1, weight = 20 },
        },
        rare = { item = 'gold_bar', chance = 0.015 },
    },
    salvage = {
        label = 'Scrapyard', time = 4000, scenario = 'WORLD_HUMAN_WELDING',
        blip = { sprite = 365, color = 47, scale = 0.7 },
        yields = {
            { item = 'metal_scrap', min = 1, max = 3, weight = 55 },
            { item = 'plastic',     min = 1, max = 2, weight = 50 },
            { item = 'rubber',      min = 1, max = 2, weight = 40 },
            { item = 'glass',       min = 1, max = 1, weight = 30 },
            { item = 'brass',       min = 1, max = 1, weight = 25 },
            { item = 'cable',       min = 1, max = 1, weight = 20 },
        },
        rare = { item = 'electronics', chance = 0.05 },
    },
    textile = {
        label = 'Cotton Field', time = 3500, scenario = 'WORLD_HUMAN_GARDENER_PLANT',
        blip = { sprite = 496, color = 25, scale = 0.7 },
        yields = {
            { item = 'cotton', min = 1, max = 3, weight = 60 },
            { item = 'cloth',  min = 1, max = 2, weight = 40 },
        },
    },
}

-- ── World nodes ────────────────────────────────────────────────
-- Each entry: { type = <Resources key>, coords = vector3(...) }.
Config.Nodes = {
    -- Mining — Davis Quarry
    { type = 'mining', coords = vector3(2947.7, 2789.3, 40.6) },
    { type = 'mining', coords = vector3(2957.4, 2802.6, 41.3) },
    { type = 'mining', coords = vector3(2971.2, 2789.9, 40.2) },
    -- Salvage — junk / scrap yards
    { type = 'salvage', coords = vector3(-483.0, -1700.5, 18.6) },   -- LS River channel scrap (La Puerta)
    { type = 'salvage', coords = vector3(1560.1, 3782.0, 34.1) },    -- Sandy Shores yard
    { type = 'salvage', coords = vector3(-450.0, -1690.0, 18.6) },   -- LS River channel scrap (2)
    -- Textile — Grapeseed fields
    { type = 'textile', coords = vector3(2005.3, 4988.6, 41.4) },
    { type = 'textile', coords = vector3(2039.8, 4998.1, 41.6) },
}
