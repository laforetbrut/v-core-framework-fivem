-- v-fuel | shared config
-- Owns everything fuel: the fuel TYPES, how fast a vehicle burns them, and the stations.
-- v-vehicles keeps only the stored number (persistence); it does not decide consumption.
Config = {}

Config.Distance = 3.0          -- pump interaction range (m)
Config.NozzleRange = 6.0       -- how far the car may be from the pump while fuelling

-- ── Fuel types ─────────────────────────────────────────────────
-- `price` is per litre / per kWh, before the station's own multiplier.
-- `rate` multiplies consumption: diesel engines are more efficient, electric more still.
Config.Types = {
    regular  = { i18n = 'fuel.regular',  price = 1.65, rate = 1.00, color = '#c8a55a', octane = 91 },
    premium  = { i18n = 'fuel.premium',  price = 2.10, rate = 0.92, color = '#e0603a', octane = 98 },
    diesel   = { i18n = 'fuel.diesel',   price = 1.48, rate = 0.78, color = '#6f9c5a', octane = 0 },
    electric = { i18n = 'fuel.electric', price = 0.42, rate = 0.55, color = '#4a9fe0', octane = 0 },
}
Config.TypeOrder = { 'regular', 'premium', 'diesel', 'electric' }

-- Tank size per vehicle class, in litres (kWh for electric). Used for the price maths and
-- for how long a tank lasts. GTA vehicle class ids:
--   0 compact 1 sedan 2 SUV 3 coupe 4 muscle 5 sports classic 6 sports 7 super 8 motorcycle
--   9 offroad 10 industrial 11 utility 12 van 13 bicycle 14 boat 15 helicopter 16 plane
--   17 service 18 emergency 19 military 20 commercial 21 train
Config.TankByClass = {
    [8] = 16, [13] = 0, [0] = 45, [1] = 60, [2] = 75, [3] = 60, [4] = 70, [5] = 55,
    [6] = 65, [7] = 80, [9] = 85, [10] = 150, [11] = 120, [12] = 90, [14] = 200,
    [15] = 250, [16] = 300, [17] = 100, [18] = 90, [19] = 200, [20] = 180,
}
Config.DefaultTank = 60

-- Base drain: percent of tank burned per minute at full throttle. Scaled by the fuel's
-- `rate`, by engine load and by the class multiplier below.
Config.BaseDrain = 2.4
Config.IdleDrain = 0.35        -- engine on, not moving
Config.DrainByClass = {
    [8] = 0.55, [0] = 0.80, [1] = 0.90, [2] = 1.25, [3] = 1.00, [4] = 1.35, [5] = 1.05,
    [6] = 1.30, [7] = 1.70, [9] = 1.30, [10] = 1.80, [11] = 1.55, [12] = 1.20,
    [15] = 2.20, [16] = 2.40, [17] = 1.40, [18] = 1.20, [19] = 2.00, [20] = 1.90,
}

-- ── Which fuel does a vehicle take? ────────────────────────────
-- Model overrides win; otherwise the class decides. A vehicle only accepts ONE type —
-- putting the wrong one in is a real (and recoverable) mistake, see WrongFuel below.
Config.ElectricModels = {
    'voltic', 'voltic2', 'khamelion', 'tezeract', 'cyclone', 'neon', 'raiden', 'imorgon',
    'dilettante', 'dilettante2', 'surge', 'iwagen', 'omnisegt', 'virtue', 'powersurge',
}
Config.DieselClasses = { [10] = true, [11] = true, [20] = true, [17] = true }
Config.DieselModels  = { 'phantom', 'packer', 'hauler', 'benson', 'mule', 'pounder', 'biff',
                         'rubble', 'tiptruck', 'dump', 'flatbed', 'barracks', 'bus', 'coach',
                         'airbus', 'trash', 'firetruk', 'towtruck', 'towtruck2' }
-- Everything else takes regular; premium is always accepted where regular is (it is the
-- same pump family) and gives a small engine-wear benefit.

-- Wrong fuel: the tank is not silently ruined. The engine takes damage, the mistake is
-- announced, and draining it costs a repair — not a deleted car.
Config.WrongFuel = { engineDamage = 120, refund = 0.0 }

-- ── Jerry can ──────────────────────────────────────────────────
Config.JerryCan = {
    item     = 'jerrycan',     -- inventory item, seeded like any other
    capacity = 20,             -- litres it holds
    type     = 'regular',      -- what a full can contains
    fillCost = 1.85,           -- per litre when filled at a pump
}

-- ── Stations (SEED DATA ONLY) ──────────────────────────────────
-- Points live in `world_stations` (owned by v-world) and are created, moved and priced
-- from the admin panel → Editor → Fuel stations. `types` is a comma list, `mult` scales
-- every price at that station (a remote desert pump costs more than a city one).
Config.Stations = {
    { id = 'ls_strawberry',  label = 'Xero Gas — Strawberry',      x = 265.0,   y = -1261.3, z = 29.3,  types = 'regular,premium,diesel', mult = 1.00 },
    { id = 'ls_littleseoul', label = 'Ron Oil — Little Seoul',     x = -724.6,  y = -935.1,  z = 19.2,  types = 'regular,premium',        mult = 1.00 },
    { id = 'ls_lagunapl',    label = 'Xero Gas — Laguna Place',    x = -526.0,  y = -1211.0, z = 18.2,  types = 'regular,premium,diesel', mult = 1.00 },
    { id = 'ls_vespucci',    label = 'Globe Oil — Vespucci',       x = -1437.6, y = -276.7,  z = 46.2,  types = 'regular,premium',        mult = 1.05 },
    { id = 'ls_morningwood', label = 'Ron Oil — Morningwood',      x = -1800.4, y = 803.6,   z = 138.6, types = 'regular,premium',        mult = 1.10 },
    { id = 'ls_mirrorpark',  label = 'RON — Mirror Park',          x = 1208.9,  y = -1402.5, z = 35.2,  types = 'regular,premium,diesel', mult = 1.00 },
    { id = 'ls_lsia',        label = 'Globe Oil — LSIA',           x = -319.3,  y = -1471.7, z = 30.5,  types = 'regular,premium,diesel', mult = 1.05 },
    { id = 'ls_davis',       label = 'Ron Oil — Davis',            x = 176.6,   y = -1562.1, z = 29.3,  types = 'regular,diesel',         mult = 0.95 },
    { id = 'ls_elysian',     label = 'Xero Gas — Elysian Island',  x = 819.6,   y = -1028.8, z = 26.4,  types = 'regular,diesel',         mult = 0.95 },
    { id = 'sandy_shores',   label = 'Ron Oil — Sandy Shores',     x = 1701.3,  y = 6416.0,  z = 32.7,  types = 'regular,diesel',         mult = 1.15 },
    { id = 'grapeseed',      label = 'Ron Oil — Grapeseed',        x = 1687.1,  y = 4929.3,  z = 42.1,  types = 'regular,diesel',         mult = 1.15 },
    { id = 'paleto',         label = 'Globe Oil — Paleto Bay',     x = -94.5,   y = 6419.6,  z = 31.5,  types = 'regular,premium,diesel', mult = 1.20 },
    { id = 'harmony',        label = 'Ron Oil — Route 68',         x = 1207.3,  y = 2660.2,  z = 37.9,  types = 'regular,diesel',         mult = 1.20 },
    { id = 'zancudo',        label = 'Ron Oil — Fort Zancudo Rd',  x = -2555.0, y = 2334.1,  z = 33.1,  types = 'regular,diesel',         mult = 1.25 },
    { id = 'chumash',        label = 'Globe Oil — Chumash',        x = -3038.9, y = 1043.3,  z = 20.8,  types = 'regular,premium',        mult = 1.15 },
    -- Charging points: electric only, cheap per kWh but slow.
    { id = 'ev_downtown',    label = 'Charge Point — Downtown',    x = 234.1,   y = -1013.7, z = 29.3,  types = 'electric',               mult = 1.00 },
    { id = 'ev_rockford',    label = 'Charge Point — Rockford',    x = -709.3,  y = -128.9,  z = 37.0,  types = 'electric',               mult = 1.00 },
    { id = 'ev_paleto',      label = 'Charge Point — Paleto Bay',  x = -103.1,  y = 6428.6,  z = 31.5,  types = 'electric',               mult = 1.10 },
}

Config.Blip = { sprite = 361, color = 44, scale = 0.6, evSprite = 620, evColor = 3 }
Config.Marker = { type = 21, size = 0.22, r = 255, g = 122, b = 26, a = 110 }

-- Litres per second while the nozzle is running (electric charges slower).
Config.FlowRate   = 3.2
Config.FlowRateEV = 1.1

-- ── Electric vehicles ──────────────────────────────────────────
-- A charge is not a fill. Three things make it behave like one:
--   1. a CHARGE CURVE — fast to 80 %, then deliberately slow (that is how real cells
--      protect themselves, and it is why "charge to 80" is a habit);
--   2. a CONNECTOR level — a slow AC post and a DC fast charger are different machines;
--   3. BATTERY HEALTH — an aged pack holds less than its nameplate capacity, so an old
--      EV genuinely has less range. v-mechanic owns that number (`battery_pack`).
Config.EV = {
    -- Charge speed multiplier past the knee, and where the knee sits (% of capacity).
    taperFrom  = 80,
    taperMult  = 0.35,

    -- Connector levels. `kw` drives the flow rate; `price` multiplies the per-kWh price
    -- because a fast charger costs more to use.
    connectors = {
        ac  = { i18n = 'fuel.conn_ac',   kw = 11,  price = 1.00 },
        dc  = { i18n = 'fuel.conn_dc',   kw = 50,  price = 1.25 },
        hpc = { i18n = 'fuel.conn_hpc',  kw = 150, price = 1.60 },
    },
    connectorOrder = { 'ac', 'dc', 'hpc' },
    -- kWh delivered per second, per kW of connector. Tuned so a 50 kW DC charge of a
    -- 60 kWh pack from 20 % to 80 % takes a bit over a minute of real time.
    kwhPerSecondPerKw = 0.0125,

    -- Regenerative braking recovers a little charge when slowing down.
    regen = { enabled = true, perBrakeSecond = 0.06 },

    -- An EV left with a flat pack loses a little health each time (deep discharge).
    deepDischargeWear = 1.5,
}

-- Which connectors a station offers. Anything not listed falls back to `ac` only, so a
-- station an admin creates without thinking about it is still usable.
Config.StationConnectors = {
    ev_downtown = { 'ac', 'dc', 'hpc' },
    ev_rockford = { 'ac', 'dc' },
    ev_paleto   = { 'ac' },
}
