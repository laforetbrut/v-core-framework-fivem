-- v-garages | shared config
-- SEED DATA ONLY: garage points live in `world_garages` (owned by v-world) and are
-- created, moved and deleted from the admin panel → Editor → Garages.
Config = {}

Config.Distance = 3.0
Config.Blip     = { public = 357, impound = 68, job = 357, gang = 357 }
Config.BlipColor = { public = 3, impound = 1, job = 5, gang = 27 }
Config.Marker   = { type = 21, size = 0.32, r = 255, g = 122, b = 26, a = 120 }

-- A vehicle must be roughly upright and not on fire to be stored: otherwise a player
-- could "park" a burning wreck to repair it for free.
Config.StoreMaxDamage = true

-- Real GTA V parking structures. `s*` is where a retrieved car appears.
Config.Garages = {
    { id = 'legion',   label = 'Legion Square Parking', type = 'public',
      x = 215.9,  y = -809.4, z = 30.7,  sx = 228.1,  sy = -800.2, sz = 30.6,  sh = 158.0 },
    { id = 'pillbox',  label = 'Pillbox Hill Garage',   type = 'public',
      x = 264.5,  y = -343.9, z = 44.9,  sx = 273.5,  sy = -337.2, sz = 44.9,  sh = 158.0 },
    { id = 'vespucci', label = 'Vespucci Parking',      type = 'public',
      x = -338.9, y = -893.6, z = 31.1,  sx = -329.4, sy = -888.1, sz = 30.9,  sh = 250.0 },
    { id = 'paleto',   label = 'Paleto Bay Parking',    type = 'public',
      x = 108.6,  y = 6614.4, z = 31.8,  sx = 116.3,  sy = 6620.0, sz = 31.4,  sh = 225.0 },
    { id = 'sandy',    label = 'Sandy Shores Parking',  type = 'public',
      x = 1735.9, y = 3710.3, z = 34.1,  sx = 1728.9, sy = 3715.6, sz = 34.0,  sh = 21.0 },
    { id = 'grapeseed', label = 'Grapeseed Parking',    type = 'public',
      x = 1701.1, y = 4933.9, z = 42.0,  sx = 1694.6, sy = 4928.5, sz = 42.0,  sh = 240.0 },
    -- Impound: the only way a vehicle marked `impound` comes back, and it costs.
    { id = 'impound',  label = 'City Impound Lot',      type = 'impound', fee = 750,
      x = 408.9,  y = -1622.9, z = 29.3, sx = 401.6,  sy = -1630.2, sz = 29.3, sh = 230.0 },
    -- Job motor pools — locked to the job that owns them.
    { id = 'pd_motorpool',  label = 'LSPD Motor Pool',  type = 'job', job = 'police',
      x = 454.5,  y = -1017.4, z = 28.4, sx = 438.4,  sy = -1018.3, sz = 28.7, sh = 90.0 },
    { id = 'ems_motorpool', label = 'EMS Motor Pool',   type = 'job', job = 'ambulance',
      x = 294.4,  y = -600.4, z = 43.3,  sx = 302.1,  sy = -602.5, sz = 43.3,  sh = 65.0 },
}
