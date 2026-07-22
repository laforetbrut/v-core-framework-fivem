-- v-cityhall | shared config
-- The city hall is where a civilian picks up an open job. Which jobs are open is NOT
-- configured here: it comes from the `jobs` table (v-world), where a job flagged
-- `whitelisted` is hidden — those are handed out by their own chain of command.
Config = {}

Config.Distance = 2.2         -- interaction range (m)

-- Real Los Santos civic buildings. Coordinates are vector4(x, y, z, heading).
Config.Locations = {
    { label = 'cityhall.ls',      x = -544.85, y = -204.35, z = 38.22, h = 205.0 },  -- LS City Hall
    { label = 'cityhall.sandy',   x = 1693.10, y = 3585.70, z = 35.62, h = 208.0 },  -- Sandy Shores town office
    { label = 'cityhall.paleto',  x = -437.30, y = 6046.10, z = 31.34, h = 226.0 },  -- Paleto Bay town office
}

-- Clerk behind the desk. Set to nil for a location to run without a ped.
Config.Ped = 'a_f_y_business_02'

Config.Blip = { sprite = 419, color = 4, scale = 0.75 }

Config.Marker = { type = 21, size = 0.28, r = 255, g = 122, b = 26, a = 120 }

-- Resigning is free; hiring may cost a filing fee (paid from cash, 0 = free).
Config.HireFee = 0

-- A job in this list can never be taken at the city hall even if it isn't whitelisted
-- in the DB — a hard floor that survives an admin mistake in the editor.
Config.NeverPublic = { 'unemployed' }
