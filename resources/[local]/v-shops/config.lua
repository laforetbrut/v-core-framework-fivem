-- v-shops | shared config
Config = {}

Config.Debug = false

-- Interaction distance to a shop clerk.
Config.Distance = 2.2

-- Blip shown on the map for stores.
Config.Blip = { sprite = 52, color = 25, scale = 0.7 }

-- Physical store locations. `shop` maps to an id in the `shops` DB table
-- (which holds that store's item list & prices — editable in-game later).
Config.Locations = {
    -- 24/7 convenience stores (real GTA V locations)
    { shop = 'convenience', ped = 'mp_m_shopkeep_01', coords = vector4(25.7, -1347.3, 29.49, 270.0) },
    { shop = 'convenience', ped = 'mp_m_shopkeep_01', coords = vector4(-3038.71, 585.9, 7.9, 17.0) },
    { shop = 'convenience', ped = 'mp_m_shopkeep_01', coords = vector4(1728.66, 6414.16, 35.03, 242.0) },
    { shop = 'convenience', ped = 'mp_m_shopkeep_01', coords = vector4(1961.4, 3739.98, 32.34, 299.2) },
    { shop = 'convenience', ped = 'mp_m_shopkeep_01', coords = vector4(547.79, 2671.79, 42.15, 99.7) },
    { shop = 'convenience', ped = 'mp_m_shopkeep_01', coords = vector4(373.5, 325.6, 103.56, 256.6) },
    -- Scrap dealer (buys raw materials) — Cypress Flats industrial yard
    { shop = 'scrapyard', ped = 's_m_y_dockwork_01', coords = vector4(1057.3, -2313.6, 30.6, 179.0) },
}

-- Shops seeded into the DB at boot if the row is missing, so a sell-only dealer
-- exists without hand-writing SQL. `items` is the (JSON) buy catalogue — empty here.
Config.SeedShops = {
    { id = 'scrapyard', label = 'Scrap Dealer', type = 'materials', items = '[]' },
}

-- Sell prices: item -> unit price paid to the player. Selling reuses the same
-- proximity / job gate as buying. Only list items that exist in the catalogue.
Config.SellLists = {
    convenience = {
        apple = 2, apple_red = 2, banana = 2, bread = 2, bagel = 2, beef_jerky = 3,
    },
    scrapyard = {
        metal_scrap = 8, iron = 12, copper = 10, aluminum = 14, plastic = 5, rubber = 6,
        glass = 4, brass = 9, cable = 7, cotton = 4, cloth = 6, electronics = 20,
        nails = 2, rope = 5, gold_bar = 400,
    },
}
