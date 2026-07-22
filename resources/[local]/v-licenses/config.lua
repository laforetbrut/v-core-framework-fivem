-- v-licenses | shared config
-- One table, one export, one answer to "is this character allowed to do this".
--
-- Nothing else in the framework should invent its own permission concept for a *character*
-- capability: the dealership, the weapon shop, the PD and the city hall all ask here.
-- (v-core permissions are for STAFF; jobs are for employment; licences are for the law.)
Config = {}

-- A licence is one of these states. `valid` is what `Has()` answers true for.
Config.Status = {
    valid     = 'valid',       -- held and in date
    suspended = 'suspended',   -- temporarily taken (points, court order) — comes back
    revoked   = 'revoked',     -- taken for good; must be re-earned from scratch
    expired   = 'expired',     -- lapsed; renewable without redoing the test
}

-- Points are a demerit system: reaching `limit` suspends the licence automatically.
Config.Points = { limit = 12, suspendDays = 7 }

-- SEED DATA ONLY — types live in `license_types` (owned by v-world) and are created,
-- renamed, repriced and deleted from the admin panel → Editor → Licences.
--   key      internal name, stamped on every issued licence (immutable once created)
--   issuer   who may hand it out: 'cityhall' | 'school' | job name | 'admin'
--   price    what the issuer charges
--   days     validity in days (0 = never expires)
--   test     does it require passing something before it can be issued?
Config.Types = {
    { key = 'id_card',   i18n = 'lic.id_card',   issuer = 'cityhall', price = 50,   days = 0,   test = false, sort = 10 },
    { key = 'driving',   i18n = 'lic.driving',   issuer = 'school',   price = 750,  days = 0,   test = true,  sort = 20 },
    { key = 'motorcycle',i18n = 'lic.motorcycle',issuer = 'school',   price = 500,  days = 0,   test = true,  sort = 30 },
    { key = 'truck',     i18n = 'lic.truck',     issuer = 'school',   price = 1500, days = 0,   test = true,  sort = 40 },
    { key = 'taxi',      i18n = 'lic.taxi',      issuer = 'cityhall', price = 900,  days = 365, test = false, sort = 50 },
    { key = 'boat',      i18n = 'lic.boat',      issuer = 'school',   price = 1200, days = 0,   test = true,  sort = 60 },
    { key = 'pilot',     i18n = 'lic.pilot',     issuer = 'school',   price = 4500, days = 0,   test = true,  sort = 70 },
    { key = 'weapon',    i18n = 'lic.weapon',    issuer = 'police',   price = 2000, days = 365, test = true,  sort = 80 },
    { key = 'hunting',   i18n = 'lic.hunting',   issuer = 'cityhall', price = 400,  days = 365, test = false, sort = 90 },
    { key = 'fishing',   i18n = 'lic.fishing',   issuer = 'cityhall', price = 250,  days = 365, test = false, sort = 100 },
    { key = 'medical',   i18n = 'lic.medical',   issuer = 'ambulance',price = 0,    days = 0,   test = true,  sort = 110 },
    { key = 'bar',       i18n = 'lic.bar',       issuer = 'cityhall', price = 1800, days = 365, test = false, sort = 120 },
}

-- Which licence a vehicle class needs to be BOUGHT. Consumed by v-vehicleshop; a class
-- that isn't listed needs nothing beyond the plain driving licence.
Config.VehicleClassLicense = {
    [8]  = 'motorcycle',
    [14] = 'boat',
    [15] = 'pilot',
    [16] = 'pilot',
    [10] = 'truck',
    [20] = 'truck',
}
Config.DefaultVehicleLicense = 'driving'

-- Who may hand out a licence on behalf of an issuer. 'cityhall'/'school' are places
-- (anyone standing there can be served); anything else is a JOB — an on-duty member of
-- that job issues it, which is how a weapon permit ends up being a police decision.
Config.PlaceIssuers = { cityhall = true, school = true }

-- Driving school points (the practical test is a v-jobs/roleplay flow; this is where the
-- licence is actually granted from).
Config.School = {
    label = 'Driving School',
    x = -822.3, y = -1204.5, z = 7.3,
    blip = { sprite = 545, color = 5, scale = 0.7 },
}
