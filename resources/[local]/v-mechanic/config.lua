-- v-mechanic | shared config
-- Per-part wear, a real odometer, and the shops that put it all back together.
--
-- The model: every part has a condition 0-100. Parts wear from DISTANCE (the odometer),
-- from ABUSE (hard braking, redlining, collisions) and from NEGLECT (running on empty,
-- wrong fuel). A worn part degrades the car through the handling natives, so the player
-- feels it before the diagnostic tells them. Nothing here is cosmetic.
Config = {}

Config.Distance = 3.0
Config.Blip = { sprite = 446, color = 5, scale = 0.75 }
Config.Marker = { type = 21, size = 0.3, r = 255, g = 122, b = 26, a = 120 }

-- How often the client re-evaluates wear and re-applies the performance penalties (ms).
Config.TickMs = 4000
-- How often the accumulated wear + mileage is written back to the row (seconds).
Config.SaveInterval = 90

-- ── Wear model ─────────────────────────────────────────────────
-- Base wear is expressed per 100 km driven, then scaled by each part's `wear` factor and
-- by how the car is being driven. A gentle driver gets far more life out of a part than
-- someone who redlines it — which is the whole point of having parts at all.
Config.WearPer100km = 3.2
Config.AbuseMult = {
    redline   = 2.4,   -- sustained near-max speed
    hardBrake = 3.0,   -- braking hard from speed
    collision = 1.0,   -- handled separately, scaled by impact
    offroad   = 1.6,   -- driving off the road network
    noFuel    = 2.0,   -- running the tank dry damages the pump/injectors
}

-- Below this condition a part starts affecting the car; at 0 it fails outright.
Config.DegradeBelow = 70
-- A part under this triggers the warning light on the dashboard.
Config.WarnBelow = 35

-- ── Parts: combustion ──────────────────────────────────────────
-- `wear`     relative wear rate (1.0 = the baseline above)
-- `affects`  what degrading it costs: power | brakes | handling | electrics | cooling
-- `item`     the inventory item a mechanic consumes to replace it
-- `labour`   labour cost in $ on top of the part, charged by the shop
Config.Parts = {
    { key = 'engine',       i18n = 'mech.engine',       item = 'part_engine',       wear = 1.00, affects = 'power',     labour = 900 },
    { key = 'transmission', i18n = 'mech.transmission', item = 'part_transmission', wear = 0.55, affects = 'power',     labour = 750 },
    { key = 'clutch',       i18n = 'mech.clutch',       item = 'part_clutch',       wear = 0.80, affects = 'power',     labour = 420 },
    { key = 'turbo',        i18n = 'mech.turbo',        item = 'part_turbo',        wear = 0.70, affects = 'power',     labour = 520 },
    { key = 'injectors',    i18n = 'mech.injectors',    item = 'part_injectors',    wear = 0.65, affects = 'power',     labour = 300 },
    { key = 'sparkplugs',   i18n = 'mech.sparkplugs',   item = 'part_sparkplugs',   wear = 1.30, affects = 'power',     labour = 120 },
    { key = 'airfilter',    i18n = 'mech.airfilter',    item = 'part_airfilter',    wear = 1.50, affects = 'power',     labour = 80 },
    { key = 'oilfilter',    i18n = 'mech.oilfilter',    item = 'part_oilfilter',    wear = 1.45, affects = 'cooling',   labour = 90 },
    { key = 'fuelpump',     i18n = 'mech.fuelpump',     item = 'part_fuelpump',     wear = 0.60, affects = 'power',     labour = 340 },
    { key = 'radiator',     i18n = 'mech.radiator',     item = 'part_radiator',     wear = 0.75, affects = 'cooling',   labour = 380 },
    { key = 'exhaust',      i18n = 'mech.exhaust',      item = 'part_exhaust',      wear = 0.85, affects = 'power',     labour = 260 },
    { key = 'brakes',       i18n = 'mech.brakes',       item = 'part_brakes',       wear = 1.40, affects = 'brakes',    labour = 280 },
    { key = 'suspension',   i18n = 'mech.suspension',   item = 'part_suspension',   wear = 0.90, affects = 'handling',  labour = 460 },
    { key = 'steering',     i18n = 'mech.steering',     item = 'part_steering',     wear = 0.50, affects = 'handling',  labour = 400 },
    { key = 'axle',         i18n = 'mech.axle',         item = 'part_axle',         wear = 0.45, affects = 'handling',  labour = 520 },
    { key = 'tyres',        i18n = 'mech.tyres',        item = 'part_tyre',         wear = 1.60, affects = 'handling',  labour = 180 },
    { key = 'battery',      i18n = 'mech.battery',      item = 'part_battery',      wear = 0.55, affects = 'electrics', labour = 160 },
    { key = 'alternator',   i18n = 'mech.alternator',   item = 'part_alternator',   wear = 0.50, affects = 'electrics', labour = 300 },
    { key = 'bodywork',     i18n = 'mech.bodywork',     item = 'part_bodypanel',    wear = 0.20, affects = 'body',      labour = 340 },
    { key = 'windows',      i18n = 'mech.windows',      item = 'part_glass',        wear = 0.10, affects = 'body',      labour = 180 },
}

-- ── Parts: electric ────────────────────────────────────────────
-- An EV has no clutch, no injectors, no exhaust and no oil. It has a traction battery
-- that LOSES CAPACITY as it ages — the headline number an EV owner actually cares about.
Config.PartsEV = {
    { key = 'battery_pack', i18n = 'mech.battery_pack', item = 'part_battery_pack', wear = 0.65, affects = 'capacity',  labour = 1800 },
    { key = 'motor',        i18n = 'mech.motor',        item = 'part_motor',        wear = 0.70, affects = 'power',     labour = 1200 },
    { key = 'inverter',     i18n = 'mech.inverter',     item = 'part_inverter',     wear = 0.55, affects = 'power',     labour = 700 },
    { key = 'bms',          i18n = 'mech.bms',          item = 'part_bms',          wear = 0.45, affects = 'capacity',  labour = 520 },
    { key = 'charge_port',  i18n = 'mech.charge_port',  item = 'part_chargeport',   wear = 0.80, affects = 'charging',  labour = 240 },
    { key = 'coolant_ev',   i18n = 'mech.coolant_ev',   item = 'part_coolant',      wear = 1.10, affects = 'cooling',   labour = 150 },
    { key = 'brakes',       i18n = 'mech.brakes',       item = 'part_brakes',       wear = 0.60, affects = 'brakes',    labour = 280 },  -- regen spares them
    { key = 'suspension',   i18n = 'mech.suspension',   item = 'part_suspension',   wear = 1.05, affects = 'handling',  labour = 460 },  -- EVs are heavy
    { key = 'steering',     i18n = 'mech.steering',     item = 'part_steering',     wear = 0.50, affects = 'handling',  labour = 400 },
    { key = 'tyres',        i18n = 'mech.tyres',        item = 'part_tyre',         wear = 1.90, affects = 'handling',  labour = 180 },  -- torque + weight
    { key = 'bodywork',     i18n = 'mech.bodywork',     item = 'part_bodypanel',    wear = 0.20, affects = 'body',      labour = 340 },
    { key = 'windows',      i18n = 'mech.windows',      item = 'part_glass',        wear = 0.10, affects = 'body',      labour = 180 },
}

-- ── What a worn part costs you ─────────────────────────────────
-- Read as: at 0 condition, this system is at `floor` of its nominal value. Between
-- `Config.DegradeBelow` and 0 the penalty ramps linearly, so decay is felt gradually.
Config.Penalty = {
    power     = { floor = 0.45 },   -- engine power multiplier
    brakes    = { floor = 0.40 },   -- braking force
    handling  = { floor = 0.55 },   -- traction / grip
    electrics = { floor = 0.00 },   -- lights + starter reliability (binary-ish)
    cooling   = { floor = 0.35 },   -- overheating -> engine health bleed
    capacity  = { floor = 0.55 },   -- EV: usable battery capacity
    charging  = { floor = 0.30 },   -- EV: charge rate
    body      = { floor = 1.00 },   -- cosmetic only
}

-- ── Diagnostics & repair ───────────────────────────────────────
-- Reading a car's condition needs a tool; fixing it needs the part. A repair kit patches
-- a single part back to `kitRestore` in the field, a shop replaces it outright.
Config.DiagTool   = 'diagnostic_scanner'
Config.RepairKit  = 'repair_kit'
Config.KitRestore = 55          -- field repair ceiling: never as good as a new part
Config.KitMinimum = 15          -- a part below this cannot be patched, only replaced

-- Shops charge labour (per part, from the table above) times this multiplier. A
-- job-locked shop can be cheaper because a real mechanic is doing the work.
Config.LabourMult   = 1.00
Config.SelfServMult = 1.60      -- no mechanic on duty: you pay the premium

-- ── Odometer ───────────────────────────────────────────────────
Config.Odometer = {
    unit      = 'km',
    hudKey    = 'mech.odo',
    -- Service interval: past this many km since the last service, wear accelerates.
    service   = 5000,
    neglect   = 1.5,        -- wear multiplier past the service interval
}

-- ── Shops (SEED DATA ONLY) ─────────────────────────────────────
-- Points live in `world_mechshops` (owned by v-world), editable from the admin panel.
Config.Shops = {
    { id = 'lsc_burton',   label = 'Los Santos Customs — Burton',  x = -337.2, y = -136.6, z = 39.0,  job = 'mechanic' },
    { id = 'lsc_lamesa',   label = 'Los Santos Customs — La Mesa', x = 731.6,  y = -1088.8, z = 22.2, job = 'mechanic' },
    { id = 'benny',        label = "Benny's Original Motor Works", x = -205.6, y = -1310.5, z = 31.3, job = 'mechanic' },
    { id = 'lsc_sandy',    label = 'Los Santos Customs — Sandy',   x = 1174.9, y = 2640.3, z = 37.8,  job = nil },
    { id = 'lsc_paleto',   label = 'Los Santos Customs — Paleto',  x = 110.6,  y = 6626.0, z = 31.8,  job = nil },
    { id = 'beeker_route68', label = "Beeker's Garage — Route 68", x = 1175.0, y = 2640.0, z = 37.8,  job = nil },
}
