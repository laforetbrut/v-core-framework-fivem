-- v-rentals | shared config
-- SEED DATA ONLY: rental points live in `world_rentals` (owned by v-world) and are
-- created, moved and deleted from the admin panel → Editor → Rentals. Which models can
-- be hired, and for how much, lives on the vehicle catalogue itself (Editor → Vehicles →
-- rent deposit / rent fee) — one list, not two.
Config = {}

Config.Distance = 3.0
Config.Blip      = 225                       -- car icon
Config.BlipColor = 3
Config.Marker    = { type = 21, size = 0.32, r = 255, g = 122, b = 26, a = 120 }

-- How long a hire lasts, and what happens at the end. The deposit is the whole point:
-- it is what stops a rental being a free car with extra steps.
Config.Duration     = 60      -- minutes
Config.WarnAt       = 5       -- minutes left when the player is warned
Config.RefundOnTime = true    -- returning before the timer refunds the deposit
Config.Plate        = 'RENT'  -- temporary plate prefix; never a character_vehicles row

-- Real GTA V rental counters. `s*` is where the hired vehicle appears.
Config.Points = {
    { id = 'lsia',     label = 'Los Santos International — Car Hire', cats = 'compacts,sedans,suvs',
      x = -1037.7, y = -2737.4, z = 20.2,  sx = -1027.3, sy = -2729.5, sz = 20.2,  sh = 240.0 },
    { id = 'vespucci', label = 'Vespucci Beach Rentals',              cats = 'compacts,motorcycles',
      x = -1233.6, y = -1490.9, z = 4.4,   sx = -1226.1, sy = -1499.4, sz = 4.3,   sh = 125.0 },
    { id = 'sandy',    label = 'Sandy Shores Airfield Rentals',       cats = 'suvs,offroad',
      x = 1737.4,  y = 3308.5,  z = 41.2,  sx = 1745.2,  sy = 3315.1,  sz = 41.2,  sh = 195.0 },
    { id = 'paleto',   label = 'Paleto Bay Rentals',                  cats = 'sedans,offroad',
      x = -238.6,  y = 6199.1,  z = 31.5,  sx = -246.9,  sy = 6191.8,  sz = 31.5,  sh = 315.0 },
}

-- Applied to `vehicle_catalogue.rent_deposit` / `rent_fee` on first seed only, so an
-- operator's later edits in the admin panel are never overwritten.
Config.SeedRates = {
    -- category   deposit   fee
    compacts    = { 1200,   250 },
    sedans      = { 1800,   350 },
    suvs        = { 2600,   500 },
    offroad     = { 3000,   600 },
    motorcycles = { 1500,   300 },
}
