-- v-world | shared config
-- Admin-editable world content. Everything here is only DEFAULTS/metadata for the
-- editor UI — the live data lives in the DB (world_blips / world_shops / jobs).
Config = {}

Config.Debug = false

-- Permission required to open the editor and mutate world content.
Config.Permission = 'admin'

-- Handy blip sprite presets shown in the admin editor (label -> sprite id).
-- Full list: https://docs.fivem.net/docs/game-references/blips/
Config.BlipPresets = {
    { label = 'Marker',        sprite = 1 },
    { label = 'Store (24/7)',  sprite = 52 },
    { label = 'Clothing',      sprite = 73 },
    { label = 'Garage',        sprite = 357 },
    { label = 'Bank',          sprite = 108 },
    { label = 'Hospital',      sprite = 61 },
    { label = 'Police',        sprite = 60 },
    { label = 'Mechanic',      sprite = 446 },
    { label = 'Ammunation',    sprite = 110 },
    { label = 'Bar',           sprite = 93 },
    { label = 'Restaurant',    sprite = 106 },
    { label = 'Workbench',     sprite = 566 },
    { label = 'Scrapyard',     sprite = 365 },
    { label = 'Fuel',          sprite = 361 },
    { label = 'Job',           sprite = 351 },
}

-- Common blip colours for the editor picker (label -> colour id).
Config.BlipColors = {
    { label = 'White',  color = 0 },  { label = 'Red',    color = 1 },
    { label = 'Green',  color = 2 },  { label = 'Blue',   color = 3 },
    { label = 'Yellow', color = 5 },  { label = 'Orange', color = 47 },
    { label = 'Purple', color = 27 }, { label = 'Pink',   color = 48 },
    { label = 'Grey',   color = 40 }, { label = 'Cyan',   color = 26 },
}
