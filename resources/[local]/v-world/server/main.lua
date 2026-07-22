-- v-world | server
-- Single owner of the admin-editable world content:
--   * world_blips  — free-form map blips
--   * world_shops  — shop/store locations (v-shops consumes them)
--   * jobs         — jobs + grades + salaries (v-jobs consumes them)
--   * world_clothing       — clothing store locations (v-clothing consumes them)
--   * clothing_categories  — the wearable slots themselves (v-clothing consumes them)
--
-- Each domain is SEEDED from the owning module's static config the first time the
-- table is empty, so behaviour is identical to the hardcoded setup until an admin
-- edits something. Every mutation reloads the cache, notifies the owning modules
-- (`v-world:server:changed`) and pushes a live sync to clients — no restart.
local Core = exports['v-core']:GetCore()

local Blips, ShopLocs, Jobs, Items, Recipes = {}, {}, {}, {}, {}
local Gangs, Turfs = {}, {}
local ClothStores, ClothCats = {}, {}
local Garages, Stations, MechShops = {}, {}, {}
local LicTypes = {}
local Dealers, VehCat = {}, {}
local Rentals = {}
local UiThemes = {}
local ready = false

local function isAdmin(src)
    if src == 0 then return true end   -- console
    return Core.HasPermission(src, Config.Permission or 'admin')
end

-- ── Schema (idempotent: works even on a DB created before v-world existed) ──
local function ensureTables()
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS `world_blips` (
        `id` INT NOT NULL AUTO_INCREMENT,
        `label` VARCHAR(80) NOT NULL,
        `sprite` INT NOT NULL DEFAULT 1,
        `color` INT NOT NULL DEFAULT 0,
        `scale` FLOAT NOT NULL DEFAULT 0.8,
        `x` FLOAT NOT NULL, `y` FLOAT NOT NULL, `z` FLOAT NOT NULL,
        `shortrange` TINYINT(1) NOT NULL DEFAULT 1,
        `enabled` TINYINT(1) NOT NULL DEFAULT 1,
        `job` VARCHAR(50) DEFAULT NULL,                   -- visible only to this job (NULL = everyone)
        `grade` INT NOT NULL DEFAULT 0,                   -- minimum grade within that job
        `perm` VARCHAR(24) DEFAULT NULL,                  -- visible only from this permission tier up
        `created_by` VARCHAR(24) DEFAULT NULL,
        PRIMARY KEY (`id`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])

    -- `jobs.whitelisted` — a whitelisted job cannot be taken freely at the city hall.
    if not MySQL.scalar.await(
        'SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ? AND COLUMN_NAME = ?',
        { 'jobs', 'whitelisted' }) then
        MySQL.query.await('ALTER TABLE `jobs` ADD COLUMN `whitelisted` TINYINT(1) NOT NULL DEFAULT 0')
        -- Backfill, in the same migration: rows that pre-date the column all default to 0,
        -- which would leave police and EMS handed out at the city hall to anyone. Any job
        -- that is not a plain civilian one starts whitelisted, matching the seed rule.
        local n = MySQL.update.await("UPDATE `jobs` SET `whitelisted` = 1 WHERE `type` IS NOT NULL AND `type` <> 'civ'")
        if n and n > 0 then
            print(('[v-world] backfilled whitelisted=1 on %d pre-existing non-civ job(s)'):format(n))
        end
    end

    -- v-mechanic stores per-part condition, the odometer and the last service on the
    -- vehicle row itself: it is the same object, and a separate table would let the two
    -- drift apart on delete.
    for _, col in ipairs({
        { 'parts',        "ADD COLUMN `parts` JSON DEFAULT NULL" },
        { 'mileage',      "ADD COLUMN `mileage` DOUBLE NOT NULL DEFAULT 0" },
        { 'last_service', "ADD COLUMN `last_service` DOUBLE NOT NULL DEFAULT 0" },
    }) do
        local has = MySQL.scalar.await(
            'SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ? AND COLUMN_NAME = ?',
            { 'character_vehicles', col[1] })
        if not has then MySQL.query.await('ALTER TABLE `character_vehicles` ' .. col[2]) end
    end

    -- Upgrade path for a world_blips created before visibility gating existed.
    for _, col in ipairs({
        { 'job',   "ADD COLUMN `job` VARCHAR(50) DEFAULT NULL" },
        { 'grade', "ADD COLUMN `grade` INT NOT NULL DEFAULT 0" },
        { 'perm',  "ADD COLUMN `perm` VARCHAR(24) DEFAULT NULL" },
    }) do
        local has = MySQL.scalar.await(
            'SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ? AND COLUMN_NAME = ?',
            { 'world_blips', col[1] })
        if not has then MySQL.query.await('ALTER TABLE `world_blips` ' .. col[2]) end
    end

    MySQL.query.await([[CREATE TABLE IF NOT EXISTS `world_shops` (
        `id` INT NOT NULL AUTO_INCREMENT,
        `shop` VARCHAR(50) NOT NULL,
        `x` FLOAT NOT NULL, `y` FLOAT NOT NULL, `z` FLOAT NOT NULL, `h` FLOAT NOT NULL DEFAULT 0,
        `ped` VARCHAR(60) DEFAULT NULL,
        `blip` TINYINT(1) NOT NULL DEFAULT 1,
        `enabled` TINYINT(1) NOT NULL DEFAULT 1,
        PRIMARY KEY (`id`), KEY `shop_idx` (`shop`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])

    MySQL.query.await([[CREATE TABLE IF NOT EXISTS `world_clothing` (
        `id` INT NOT NULL AUTO_INCREMENT,
        `label` VARCHAR(80) NOT NULL DEFAULT 'Clothing Store',
        `x` FLOAT NOT NULL, `y` FLOAT NOT NULL, `z` FLOAT NOT NULL, `h` FLOAT NOT NULL DEFAULT 0,
        `ped` VARCHAR(60) DEFAULT NULL,
        `blip` TINYINT(1) NOT NULL DEFAULT 1,
        `job` VARCHAR(50) DEFAULT NULL,                   -- job-locked store (NULL = open to all)
        `enabled` TINYINT(1) NOT NULL DEFAULT 1,
        PRIMARY KEY (`id`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])

    -- The wearable slots. `kind`+`slot` is the GTA component/prop id; several
    -- categories may legitimately share one (gloves and bare arms are both
    -- component 3 — the ped can only render one, which is exactly how gloves work).
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS `clothing_categories` (
        `key`   VARCHAR(30) NOT NULL,
        `label` VARCHAR(60) NOT NULL,
        `kind`  VARCHAR(4)  NOT NULL DEFAULT 'comp',      -- comp | prop
        `slot`  INT NOT NULL,
        `item`  VARCHAR(50) NOT NULL,                     -- inventory item this category mints
        `price` INT NOT NULL DEFAULT 0,
        `framing` VARCHAR(10) NOT NULL DEFAULT 'body',    -- thumbnail camera framing
        `sort`  INT NOT NULL DEFAULT 0,
        `enabled` TINYINT(1) NOT NULL DEFAULT 1,
        PRIMARY KEY (`key`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])

    -- Garage points. `spawn*` is where a retrieved car appears (kept separate from the
    -- interaction point so a garage can sit indoors and spawn on the street outside).
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS `world_garages` (
        `id` VARCHAR(40) NOT NULL,
        `label` VARCHAR(80) NOT NULL,
        `type` VARCHAR(12) NOT NULL DEFAULT 'public',     -- public | job | gang | impound
        `x` FLOAT NOT NULL, `y` FLOAT NOT NULL, `z` FLOAT NOT NULL,
        `sx` FLOAT NOT NULL, `sy` FLOAT NOT NULL, `sz` FLOAT NOT NULL, `sh` FLOAT NOT NULL DEFAULT 0,
        `blip` TINYINT(1) NOT NULL DEFAULT 1,
        `job` VARCHAR(50) DEFAULT NULL,                   -- job/gang lock (NULL = open to all)
        `fee` INT NOT NULL DEFAULT 0,                     -- release fee (impound)
        `enabled` TINYINT(1) NOT NULL DEFAULT 1,
        PRIMARY KEY (`id`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])

    -- Fuel / charging points. `types` is a comma list of fuel type keys and `mult`
    -- scales every price at this station, so a desert pump can cost more than a city one.
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS `world_stations` (
        `id` VARCHAR(40) NOT NULL,
        `label` VARCHAR(80) NOT NULL,
        `x` FLOAT NOT NULL, `y` FLOAT NOT NULL, `z` FLOAT NOT NULL,
        `types` VARCHAR(120) NOT NULL DEFAULT 'regular',
        `mult` FLOAT NOT NULL DEFAULT 1.0,
        `blip` TINYINT(1) NOT NULL DEFAULT 1,
        `enabled` TINYINT(1) NOT NULL DEFAULT 1,
        PRIMARY KEY (`id`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])

    MySQL.query.await([[CREATE TABLE IF NOT EXISTS `world_mechshops` (
        `id` VARCHAR(40) NOT NULL,
        `label` VARCHAR(80) NOT NULL,
        `x` FLOAT NOT NULL, `y` FLOAT NOT NULL, `z` FLOAT NOT NULL,
        `blip` TINYINT(1) NOT NULL DEFAULT 1,
        `job` VARCHAR(50) DEFAULT NULL,                   -- staffed shop (NULL = self-service)
        `mult` FLOAT NOT NULL DEFAULT 1.0,                -- labour price multiplier
        `enabled` TINYINT(1) NOT NULL DEFAULT 1,
        PRIMARY KEY (`id`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])

    -- The licence CATALOGUE (what kinds exist). Issued licences live on
    -- `character_licenses`, owned by v-licenses.
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS `license_types` (
        `key`    VARCHAR(40) NOT NULL,
        `label`  VARCHAR(80) NOT NULL,
        `issuer` VARCHAR(50) NOT NULL DEFAULT 'cityhall',
        `price`  INT NOT NULL DEFAULT 0,
        `days`   INT NOT NULL DEFAULT 0,               -- 0 = never expires
        `test`   TINYINT(1) NOT NULL DEFAULT 0,
        `sort`   INT NOT NULL DEFAULT 0,
        `enabled` TINYINT(1) NOT NULL DEFAULT 1,
        PRIMARY KEY (`key`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])

    MySQL.query.await([[CREATE TABLE IF NOT EXISTS `character_licenses` (
        `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
        `citizenid` VARCHAR(16) NOT NULL,
        `type`   VARCHAR(40) NOT NULL,
        `status` VARCHAR(12) NOT NULL DEFAULT 'valid',
        `points` INT NOT NULL DEFAULT 0,
        `issued_at`  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        `expires_at` TIMESTAMP NULL DEFAULT NULL,
        `issuer` VARCHAR(24) DEFAULT NULL,
        PRIMARY KEY (`id`),
        UNIQUE KEY `cid_type` (`citizenid`, `type`),
        KEY `citizenid` (`citizenid`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])

    MySQL.query.await([[CREATE TABLE IF NOT EXISTS `world_dealers` (
        `id` VARCHAR(40) NOT NULL,
        `label` VARCHAR(80) NOT NULL,
        `x` FLOAT NOT NULL, `y` FLOAT NOT NULL, `z` FLOAT NOT NULL,
        `sx` FLOAT NOT NULL, `sy` FLOAT NOT NULL, `sz` FLOAT NOT NULL, `sh` FLOAT NOT NULL DEFAULT 0,
        `cats` VARCHAR(200) NOT NULL DEFAULT '',        -- comma list; empty = sells everything
        `blip` TINYINT(1) NOT NULL DEFAULT 1,
        `job` VARCHAR(50) DEFAULT NULL,                 -- job-only dealer (police motor pool, …)
        `enabled` TINYINT(1) NOT NULL DEFAULT 1,
        PRIMARY KEY (`id`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])

    -- The catalogue: what can be bought at all, and for how much.
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS `vehicle_catalogue` (
        `model` VARCHAR(50) NOT NULL,
        `label` VARCHAR(80) NOT NULL,
        `cat`   VARCHAR(30) NOT NULL DEFAULT 'sedans',
        `price` INT NOT NULL DEFAULT 0,
        `stock` INT NOT NULL DEFAULT -1,                -- -1 = unlimited
        `license` VARCHAR(40) DEFAULT NULL,             -- overrides the class default
        `job`   VARCHAR(50) DEFAULT NULL,               -- job-restricted purchase
        `enabled` TINYINT(1) NOT NULL DEFAULT 1,
        PRIMARY KEY (`model`), KEY `cat_idx` (`cat`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])

    -- Rental points. `cats` is a comma list of vehicle categories this point hires
    -- out; empty means anything the catalogue marks rentable.
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS `world_rentals` (
        `id` VARCHAR(40) NOT NULL,
        `label` VARCHAR(80) NOT NULL,
        `x` FLOAT NOT NULL, `y` FLOAT NOT NULL, `z` FLOAT NOT NULL,
        `sx` FLOAT NOT NULL, `sy` FLOAT NOT NULL, `sz` FLOAT NOT NULL, `sh` FLOAT NOT NULL DEFAULT 0,
        `cats` VARCHAR(200) NOT NULL DEFAULT '',
        `blip` TINYINT(1) NOT NULL DEFAULT 1,
        `job` VARCHAR(50) DEFAULT NULL,
        `enabled` TINYINT(1) NOT NULL DEFAULT 1,
        PRIMARY KEY (`id`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])

    -- Rentability rides on the vehicle catalogue rather than a second list: one row per
    -- model, edited in one place. NULL deposit = this model cannot be hired.
    for _, col in ipairs({
        { 'rent_deposit', "ADD COLUMN `rent_deposit` INT DEFAULT NULL" },
        { 'rent_fee',     "ADD COLUMN `rent_fee` INT DEFAULT NULL" },
    }) do
        local has = MySQL.scalar.await(
            'SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ? AND COLUMN_NAME = ?',
            { 'vehicle_catalogue', col[1] })
        if not has then MySQL.query.await('ALTER TABLE `vehicle_catalogue` ' .. col[2]) end
    end

    -- Gang territory. A turf is a circle rather than a polygon on purpose: the capture
    -- rule only ever asks "who is standing inside", and a radius answers that in one
    -- distance check per player instead of a point-in-polygon test every tick.
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS `world_turfs` (
        `id` VARCHAR(40) NOT NULL,
        `label` VARCHAR(80) NOT NULL,
        `x` FLOAT NOT NULL, `y` FLOAT NOT NULL, `z` FLOAT NOT NULL,
        `radius` FLOAT NOT NULL DEFAULT 90.0,
        `blip` TINYINT(1) NOT NULL DEFAULT 1,
        `enabled` TINYINT(1) NOT NULL DEFAULT 1,
        PRIMARY KEY (`id`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])

    -- How many defaults each domain was last seeded with. See `seedNeeded` below.
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS `world_seeded` (
        `domain` VARCHAR(40) NOT NULL,
        `count`  INT NOT NULL DEFAULT 0,
        `at`     TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        PRIMARY KEY (`domain`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])

    -- Per-module theme overrides. Every column is nullable on purpose: NULL means
    -- "inherit the global theme", so a row only carries what genuinely differs.
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS `ui_overrides` (
        `module`  VARCHAR(64) NOT NULL,
        `preset`  VARCHAR(32) DEFAULT NULL,
        `accent`  VARCHAR(9)  DEFAULT NULL,
        `panel_alpha`    FLOAT DEFAULT NULL,
        `backdrop_alpha` FLOAT DEFAULT NULL,
        `radius`  FLOAT DEFAULT NULL,
        `motion`  FLOAT DEFAULT NULL,
        `font_scale` FLOAT DEFAULT NULL,
        `enabled` TINYINT(1) NOT NULL DEFAULT 1,
        PRIMARY KEY (`module`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])

    MySQL.query.await([[CREATE TABLE IF NOT EXISTS `craft_recipes` (
        `id` INT NOT NULL AUTO_INCREMENT,
        `station` VARCHAR(40) NOT NULL,
        `output`  VARCHAR(60) NOT NULL,
        `count`   INT NOT NULL DEFAULT 1,
        `time`    INT NOT NULL DEFAULT 3000,
        `inputs`  JSON NOT NULL,                          -- { itemName: qty, ... }
        `enabled` TINYINT(1) NOT NULL DEFAULT 1,
        PRIMARY KEY (`id`), KEY `station_idx` (`station`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
end

-- ── Load caches ────────────────────────────────────────────────
local function bool(v) return (v == true or v == 1) and 1 or 0 end

-- ── Seeding ────────────────────────────────────────────────────
-- The old guard was "is the table empty", which meant a table populated by an earlier
-- version never gained anything the config added later. Instead, remember how many
-- defaults a domain was last seeded with and re-run when that number changes. Every seed
-- insert is INSERT IGNORE, so re-running never touches an existing row — it only fills in
-- what is genuinely new. A default an admin deleted stays deleted until the config itself
-- changes, which is the behaviour the original guard was protecting.
local function countOf(defaults)
    local n = 0
    for _ in pairs(defaults or {}) do n = n + 1 end
    return n
end

local function seedNeeded(domain, defaults)
    local want = countOf(defaults)
    local have = MySQL.scalar.await('SELECT `count` FROM world_seeded WHERE domain = ?', { domain })
    if have and tonumber(have) == want then return false end
    return true, want
end

local function seedDone(domain, want)
    MySQL.query.await([[INSERT INTO world_seeded (domain, `count`) VALUES (?,?)
        ON DUPLICATE KEY UPDATE `count` = VALUES(`count`)]], { domain, want })
end

local function loadBlips()
    Blips = {}
    for _, r in ipairs(MySQL.query.await('SELECT * FROM world_blips ORDER BY id') or {}) do
        r.shortrange, r.enabled = bool(r.shortrange), bool(r.enabled)
        Blips[#Blips + 1] = r
    end
end

local function loadShops()
    ShopLocs = {}
    for _, r in ipairs(MySQL.query.await('SELECT * FROM world_shops ORDER BY id') or {}) do
        r.blip, r.enabled = bool(r.blip), bool(r.enabled)
        ShopLocs[#ShopLocs + 1] = r
    end
end

local function loadJobs()
    Jobs = {}
    for _, r in ipairs(MySQL.query.await('SELECT * FROM jobs ORDER BY name') or {}) do
        local g = r.grades
        if type(g) == 'string' then g = json.decode(g) or {} end
        r.grades = g or {}
        r.whitelisted = bool(r.whitelisted)
        Jobs[#Jobs + 1] = r
    end
end

local function loadGangs()
    Gangs = {}
    for _, r in ipairs(MySQL.query.await('SELECT * FROM gangs ORDER BY name') or {}) do
        local g = r.grades
        if type(g) == 'string' then g = json.decode(g) or {} end
        r.grades = g or {}
        Gangs[#Gangs + 1] = r
    end
end

local function loadTurfs()
    Turfs = {}
    for _, r in ipairs(MySQL.query.await('SELECT * FROM world_turfs ORDER BY label') or {}) do
        r.blip, r.enabled = bool(r.blip), bool(r.enabled)
        Turfs[#Turfs + 1] = r
    end
end

local function loadItems()
    Items = {}
    for _, r in ipairs(MySQL.query.await('SELECT * FROM items ORDER BY category, name') or {}) do
        local m = r.metadata
        if type(m) == 'string' then m = json.decode(m) or {} end
        r.metadata = m or {}
        r.stackable = bool(r.stackable)
        r.usable    = bool(r.usable)
        Items[#Items + 1] = r
    end
end

local function loadRecipes()
    Recipes = {}
    for _, r in ipairs(MySQL.query.await('SELECT * FROM craft_recipes ORDER BY station, id') or {}) do
        local i = r.inputs
        if type(i) == 'string' then i = json.decode(i) or {} end
        r.inputs  = i or {}
        r.enabled = bool(r.enabled)
        Recipes[#Recipes + 1] = r
    end
end

local function loadClothStores()
    ClothStores = {}
    for _, r in ipairs(MySQL.query.await('SELECT * FROM world_clothing ORDER BY id') or {}) do
        r.blip, r.enabled = bool(r.blip), bool(r.enabled)
        ClothStores[#ClothStores + 1] = r
    end
end

local function loadClothCats()
    ClothCats = {}
    for _, r in ipairs(MySQL.query.await('SELECT * FROM clothing_categories ORDER BY sort, `key`') or {}) do
        r.enabled = bool(r.enabled)
        ClothCats[#ClothCats + 1] = r
    end
end

local function loadGarages()
    Garages = {}
    for _, r in ipairs(MySQL.query.await('SELECT * FROM world_garages ORDER BY label') or {}) do
        r.blip, r.enabled = bool(r.blip), bool(r.enabled)
        Garages[#Garages + 1] = r
    end
end

local function loadStations()
    Stations = {}
    for _, r in ipairs(MySQL.query.await('SELECT * FROM world_stations ORDER BY label') or {}) do
        r.blip, r.enabled = bool(r.blip), bool(r.enabled)
        Stations[#Stations + 1] = r
    end
end

local function loadMechShops()
    MechShops = {}
    for _, r in ipairs(MySQL.query.await('SELECT * FROM world_mechshops ORDER BY label') or {}) do
        r.blip, r.enabled = bool(r.blip), bool(r.enabled)
        MechShops[#MechShops + 1] = r
    end
end

local function loadLicTypes()
    LicTypes = {}
    for _, r in ipairs(MySQL.query.await('SELECT * FROM license_types ORDER BY sort, `key`') or {}) do
        r.test, r.enabled = bool(r.test), bool(r.enabled)
        LicTypes[#LicTypes + 1] = r
    end
end

local function loadDealers()
    Dealers = {}
    for _, r in ipairs(MySQL.query.await('SELECT * FROM world_dealers ORDER BY label') or {}) do
        r.blip, r.enabled = bool(r.blip), bool(r.enabled)
        Dealers[#Dealers + 1] = r
    end
end

local function loadRentals()
    Rentals = {}
    for _, r in ipairs(MySQL.query.await('SELECT * FROM world_rentals ORDER BY label') or {}) do
        r.blip, r.enabled = bool(r.blip), bool(r.enabled)
        Rentals[#Rentals + 1] = r
    end
end

local function loadVehCat()
    VehCat = {}
    for _, r in ipairs(MySQL.query.await('SELECT * FROM vehicle_catalogue ORDER BY cat, price') or {}) do
        r.enabled = bool(r.enabled)
        VehCat[#VehCat + 1] = r
    end
end

local function loadUiThemes()
    UiThemes = {}
    for _, r in ipairs(MySQL.query.await('SELECT * FROM ui_overrides ORDER BY `module`') or {}) do
        r.enabled = bool(r.enabled)
        UiThemes[#UiThemes + 1] = r
    end
end

local function reload(domain)
    if domain == 'blips'   or not domain then loadBlips() end
    if domain == 'shops'   or not domain then loadShops() end
    if domain == 'jobs'    or not domain then loadJobs() end
    if domain == 'gangs'   or not domain then loadGangs() end
    if domain == 'turfs'   or not domain then loadTurfs() end
    if domain == 'items'   or not domain then loadItems() end
    if domain == 'recipes' or not domain then loadRecipes() end
    if domain == 'clothstores' or not domain then loadClothStores() end
    if domain == 'clothcats'   or not domain then loadClothCats() end
    if domain == 'garages'     or not domain then loadGarages() end
    if domain == 'stations'    or not domain then loadStations() end
    if domain == 'mechshops'   or not domain then loadMechShops() end
    if domain == 'licenses'    or not domain then loadLicTypes() end
    if domain == 'dealers'     or not domain then loadDealers() end
    if domain == 'vehcat'      or not domain then loadVehCat() end
    if domain == 'rentals'     or not domain then loadRentals() end
    if domain == 'uitheme'     or not domain then loadUiThemes() end
end

-- ── Blip visibility ────────────────────────────────────────────
-- A blip may be restricted to a job (with a minimum grade) and/or a permission tier.
-- The filtering is done SERVER-SIDE, per player: a restricted location is never sent to
-- someone who isn't allowed to see it, so it can't be read out of the client's memory.
local function canSeeBlip(src, r)
    if r.perm and r.perm ~= '' and not Core.HasPermission(src, r.perm) then return false end
    if r.job and r.job ~= '' then
        local p = Core.GetPlayer(src)
        -- player.job is a table { name, grade }, not a string
        local job = p and p.job
        if not job or job.name ~= r.job then return false end
        if (tonumber(job.grade) or 0) < (tonumber(r.grade) or 0) then return false end
    end
    return true
end

local function blipsFor(src)
    local out = {}
    for _, r in ipairs(Blips) do
        if r.enabled == 1 and canSeeBlip(src, r) then out[#out + 1] = r end
    end
    return out
end

-- Push the visible subset to one player, or to everyone when `target` is omitted.
local function pushBlips(target)
    if target then
        TriggerClientEvent('v-world:client:blips', target, blipsFor(target))
        return
    end
    for _, src in ipairs(GetPlayers()) do
        src = tonumber(src)
        TriggerClientEvent('v-world:client:blips', src, blipsFor(src))
    end
end
exports('RefreshBlipsFor', function(src) pushBlips(tonumber(src)) end)

-- Push blips to clients and tell the owning modules to re-read their data.
local function broadcast(domain)
    if domain == 'blips' or not domain then pushBlips() end
    TriggerEvent('v-world:server:changed', domain)
end

-- A player's job changed → their restricted blips may have appeared or disappeared.
AddEventHandler('v-jobs:server:changed', function(src) pushBlips(tonumber(src)) end)
AddEventHandler('v-core:server:permissionChanged', function(src) pushBlips(tonumber(src)) end)

-- ── Boot ───────────────────────────────────────────────────────
CreateThread(function()
    while GetResourceState('oxmysql') ~= 'started' do Wait(100) end
    ensureTables()
    reload()
    ready = true
    Wait(1500)                       -- let the owning modules seed their defaults first
    broadcast()
end)

exports('IsReady', function() return ready end)
--- Reload one domain from outside v-world (a module that wrote to a v-world table
--- itself — the vehicle scan importer, for instance — and needs the cache refreshed).
exports('RefreshDomain', function(domain)
    if not ready then return false end
    reload(domain); broadcast(domain)
    return true
end)
exports('GetBlips', function() return Blips end)
exports('GetShopLocations', function() return ShopLocs end)
exports('GetJobs', function() return Jobs end)
exports('GetItems', function() return Items end)
exports('GetRecipes', function() return Recipes end)
exports('GetClothStores', function() return ClothStores end)
exports('GetClothCategories', function() return ClothCats end)
exports('GetGangs',   function() return Gangs end)
exports('GetTurfs',   function() return Turfs end)
exports('GetRentals', function() return Rentals end)
exports('GetGarages', function() return Garages end)
exports('GetStations', function() return Stations end)
exports('GetMechShops', function() return MechShops end)
exports('GetLicenseTypes', function() return LicTypes end)
exports('GetDealers', function() return Dealers end)
exports('GetVehicleCatalogue', function() return VehCat end)
exports('GetUiThemes', function() return UiThemes end)

-- v-crafting: list of { station, output, count, time, inputs = { item = qty } }
exports('SeedRecipes', function(defaults)
    if not ready or type(defaults) ~= 'table' then return false end
    -- This table keys on an AUTO_INCREMENT id, so INSERT IGNORE cannot dedupe and a
    -- re-run would duplicate every row. It seeds once, when genuinely empty.
    if #Recipes > 0 then return false end
    local want = countOf(defaults)
    for _, r in ipairs(defaults) do
        MySQL.insert.await(
            'INSERT INTO craft_recipes (station, output, count, time, inputs, enabled) VALUES (?,?,?,?,?,1)',
            { r.station, r.output, r.count or 1, r.time or 3000, json.encode(r.inputs or {}) })
    end
    seedDone('recipes', want)
    loadRecipes()
    print(('[v-world] seeded %d craft recipe(s) from config'):format(#Recipes))
    return true
end)

-- ── Seeding (called ONCE by the owning module at boot, only if empty) ──
-- v-shops: list of { shop, x, y, z, h, ped, blip }
exports('SeedShopLocations', function(defaults)
    if not ready or type(defaults) ~= 'table' then return false end
    -- This table keys on an AUTO_INCREMENT id, so INSERT IGNORE cannot dedupe and a
    -- re-run would duplicate every row. It seeds once, when genuinely empty.
    if #ShopLocs > 0 then return false end
    local want = countOf(defaults)                       -- already managed in DB
    for _, l in ipairs(defaults) do
        MySQL.insert.await(
            'INSERT INTO world_shops (shop, x, y, z, h, ped, blip, enabled) VALUES (?,?,?,?,?,?,?,1)',
            { l.shop, l.x, l.y, l.z, l.h or 0.0, l.ped, bool(l.blip == nil or l.blip) })
    end
    seedDone('shops', want)
    loadShops()
    print(('[v-world] seeded %d shop location(s) from config'):format(#ShopLocs))
    return true
end)

-- v-jobs: map jobId -> { label, grades = { [n] = { name, salary } } }
-- v-clothing: list of { x, y, z, h, label?, ped? }
exports('SeedClothStores', function(defaults)
    if not ready or type(defaults) ~= 'table' then return false end
    -- This table keys on an AUTO_INCREMENT id, so INSERT IGNORE cannot dedupe and a
    -- re-run would duplicate every row. It seeds once, when genuinely empty.
    if #ClothStores > 0 then return false end
    local want = countOf(defaults)
    for _, l in ipairs(defaults) do
        MySQL.insert.await('INSERT INTO world_clothing (label, x, y, z, h, ped, blip, enabled) VALUES (?,?,?,?,?,?,1,1)',
            { l.label or 'Clothing Store', l.x, l.y, l.z, l.h or 0.0, l.ped })
    end
    seedDone('clothstores', want)
    loadClothStores()
    print(('[v-world] seeded %d clothing store(s) from config'):format(#ClothStores))
    return true
end)

-- v-clothing: list of { key, label, kind, slot, item, price, framing, sort }
exports('SeedClothCategories', function(defaults)
    if not ready or type(defaults) ~= 'table' then return false end
    local need, want = seedNeeded('clothcats', defaults)
    if not need then return false end
    for i, c in ipairs(defaults) do
        MySQL.insert.await([[INSERT IGNORE INTO clothing_categories
            (`key`, label, kind, slot, item, price, framing, sort, enabled) VALUES (?,?,?,?,?,?,?,?,1)]],
            { c.key, c.label or c.key, c.kind or 'comp', c.slot or c.id or 0, c.item or c.key,
              c.price or 0, c.framing or 'body', c.sort or i })
    end
    seedDone('clothcats', want)
    loadClothCats()
    print(('[v-world] seeded %d clothing category(ies) from config'):format(#ClothCats))
    return true
end)

-- v-rentals: list of { id, label, x, y, z, sx, sy, sz, sh, cats }
exports('SeedRentals', function(defaults)
    if not ready or type(defaults) ~= 'table' then return false end
    local need, want = seedNeeded('rentals', defaults)
    if not need then return false end
    for _, r in ipairs(defaults) do
        MySQL.insert.await([[INSERT IGNORE INTO world_rentals
            (id, label, x, y, z, sx, sy, sz, sh, cats, blip, job, enabled) VALUES (?,?,?,?,?,?,?,?,?,?,1,?,1)]],
            { r.id, r.label or r.id, r.x, r.y, r.z, r.sx, r.sy, r.sz, r.sh or 0.0,
              r.cats or '', r.job })
    end
    seedDone('rentals', want)
    loadRentals()
    print(('[v-world] seeded %d rental point(s) from config'):format(#Rentals))
    return true
end)

-- v-garages: list of { id, label, type, x, y, z, sx, sy, sz, sh, job, fee }
exports('SeedGarages', function(defaults)
    if not ready or type(defaults) ~= 'table' then return false end
    local need, want = seedNeeded('garages', defaults)
    if not need then return false end
    for _, g in ipairs(defaults) do
        MySQL.insert.await([[INSERT IGNORE INTO world_garages
            (id, label, type, x, y, z, sx, sy, sz, sh, blip, job, fee, enabled) VALUES (?,?,?,?,?,?,?,?,?,?,1,?,?,1)]],
            { g.id, g.label or g.id, g.type or 'public', g.x, g.y, g.z,
              g.sx, g.sy, g.sz, g.sh or 0.0, g.job, g.fee or 0 })
    end
    seedDone('garages', want)
    loadGarages()
    print(('[v-world] seeded %d garage(s) from config'):format(#Garages))
    return true
end)

-- v-fuel: list of { id, label, x, y, z, types, mult }
exports('SeedStations', function(defaults)
    if not ready or type(defaults) ~= 'table' then return false end
    local need, want = seedNeeded('stations', defaults)
    if not need then return false end
    for _, st in ipairs(defaults) do
        MySQL.insert.await([[INSERT IGNORE INTO world_stations (id, label, x, y, z, types, mult, blip, enabled)
            VALUES (?,?,?,?,?,?,?,1,1)]],
            { st.id, st.label or st.id, st.x, st.y, st.z, st.types or 'regular', st.mult or 1.0 })
    end
    seedDone('stations', want)
    loadStations()
    print(('[v-world] seeded %d fuel station(s) from config'):format(#Stations))
    return true
end)

-- v-mechanic: list of { id, label, x, y, z, job }
exports('SeedMechShops', function(defaults)
    if not ready or type(defaults) ~= 'table' then return false end
    local need, want = seedNeeded('mechshops', defaults)
    if not need then return false end
    for _, sh in ipairs(defaults) do
        MySQL.insert.await([[INSERT IGNORE INTO world_mechshops (id, label, x, y, z, blip, job, mult, enabled)
            VALUES (?,?,?,?,?,1,?,?,1)]],
            { sh.id, sh.label or sh.id, sh.x, sh.y, sh.z, sh.job, sh.mult or 1.0 })
    end
    seedDone('mechshops', want)
    loadMechShops()
    print(('[v-world] seeded %d mechanic shop(s) from config'):format(#MechShops))
    return true
end)

-- v-licenses: list of { key, i18n, issuer, price, days, test, sort }
exports('SeedLicenseTypes', function(defaults)
    if not ready or type(defaults) ~= 'table' then return false end
    local need, want = seedNeeded('licenses', defaults)
    if not need then return false end
    for i, t in ipairs(defaults) do
        MySQL.insert.await([[INSERT IGNORE INTO license_types (`key`, label, issuer, price, days, test, sort, enabled)
            VALUES (?,?,?,?,?,?,?,1)]],
            { t.key, t.label or t.key, t.issuer or 'cityhall', t.price or 0, t.days or 0,
              t.test and 1 or 0, t.sort or i })
    end
    seedDone('licenses', want)
    loadLicTypes()
    print(('[v-world] seeded %d licence type(s) from config'):format(#LicTypes))
    return true
end)

-- v-vehicleshop: list of { id, label, x, y, z, sx, sy, sz, sh, cats }
exports('SeedDealers', function(defaults)
    if not ready or type(defaults) ~= 'table' then return false end
    local need, want = seedNeeded('dealers', defaults)
    if not need then return false end
    for _, d in ipairs(defaults) do
        MySQL.insert.await([[INSERT IGNORE INTO world_dealers (id, label, x, y, z, sx, sy, sz, sh, cats, blip, job, enabled)
            VALUES (?,?,?,?,?,?,?,?,?,?,1,?,1)]],
            { d.id, d.label or d.id, d.x, d.y, d.z, d.sx, d.sy, d.sz, d.sh or 0.0, d.cats or '', d.job })
    end
    seedDone('dealers', want)
    loadDealers()
    print(('[v-world] seeded %d dealership(s) from config'):format(#Dealers))
    return true
end)

-- v-vehicleshop: list of { model, label, cat, price, license, job }
exports('SeedVehicleCatalogue', function(defaults)
    if not ready or type(defaults) ~= 'table' then return false end
    local need, want = seedNeeded('vehcat', defaults)
    if not need then return false end
    for _, v in ipairs(defaults) do
        MySQL.insert.await([[INSERT IGNORE INTO vehicle_catalogue (model, label, cat, price, stock, license, job, enabled)
            VALUES (?,?,?,?,?,?,?,1)]],
            { tostring(v.model):lower(), v.label or v.model, v.cat or 'sedans',
              v.price or 0, v.stock or -1, v.license, v.job })
    end
    seedDone('vehcat', want)
    loadVehCat()
    print(('[v-world] seeded %d catalogue vehicle(s) from config'):format(#VehCat))
    return true
end)

-- v-gangs: { [name] = { label, type, grades = { [n] = { name } } } }
exports('SeedGangs', function(defaults)
    if not ready or type(defaults) ~= 'table' then return false end
    local need, want = seedNeeded('gangs', defaults)
    if not need then return false end
    for name, g in pairs(defaults) do
        local arr = {}
        for n, gr in pairs(g.grades or {}) do
            arr[#arr + 1] = { grade = n, name = gr.name or ('Rank ' .. n), salary = gr.salary or 0 }
        end
        table.sort(arr, function(a, b) return a.grade < b.grade end)
        MySQL.insert.await('INSERT IGNORE INTO gangs (name, label, type, grades) VALUES (?,?,?,?)',
            { name, g.label or name, g.type or 'gang', json.encode(arr) })
    end
    seedDone('gangs', want)
    loadGangs()
    print(('[v-world] seeded %d gang(s) from config'):format(#Gangs))
    return true
end)

-- v-gangs: list of { id, label, x, y, z, radius }
exports('SeedTurfs', function(defaults)
    if not ready or type(defaults) ~= 'table' then return false end
    local need, want = seedNeeded('turfs', defaults)
    if not need then return false end
    for _, tf in ipairs(defaults) do
        MySQL.insert.await(
            'INSERT IGNORE INTO world_turfs (id, label, x, y, z, radius, blip, enabled) VALUES (?,?,?,?,?,?,1,1)',
            { tf.id, tf.label or tf.id, tf.x, tf.y, tf.z, tf.radius or 90.0 })
    end
    seedDone('turfs', want)
    loadTurfs()
    print(('[v-world] seeded %d turf(s) from config'):format(#Turfs))
    return true
end)

exports('SeedJobs', function(defaults)
    if not ready or type(defaults) ~= 'table' then return false end
    local need, want = seedNeeded('jobs', defaults)
    if not need then return false end
    for name, j in pairs(defaults) do
        local arr = {}
        for n, g in pairs(j.grades or {}) do
            arr[#arr + 1] = { grade = n, name = g.name or ('Grade ' .. n), salary = g.salary or 0 }
        end
        table.sort(arr, function(a, b) return a.grade < b.grade end)
        -- Anything that isn't a plain civilian job starts whitelisted: the city hall must
        -- not hand out a police badge to whoever walks in.
        local wl = (j.whitelisted ~= nil) and bool(j.whitelisted) or ((j.type and j.type ~= 'civ') and 1 or 0)
        MySQL.insert.await('INSERT IGNORE INTO jobs (name, label, type, grades, whitelisted) VALUES (?,?,?,?,?)',
            { name, j.label or name, j.type or 'civ', json.encode(arr), wl })
    end
    seedDone('jobs', want)
    loadJobs()
    print(('[v-world] seeded %d job(s) from config'):format(#Jobs))
    return true
end)

-- ── Admin CRUD (permission verified server-side on every call) ──
Core.RegisterCallback('v-world:list', function(source, resolve, domain)
    if not isAdmin(source) then resolve(false); return end
    if domain == 'blips' then
        -- job + permission pickers for the visibility gate
        local jobs = {}
        for _, j in ipairs(Jobs) do jobs[#jobs + 1] = { name = j.name, label = j.label } end
        resolve({ rows = Blips, presets = Config.BlipPresets, colors = Config.BlipColors,
                  jobs = jobs, perms = Config.PermTiers })
    elseif domain == 'shops' then
        local shops = MySQL.query.await('SELECT id, label FROM shops ORDER BY id') or {}
        resolve({ rows = ShopLocs, shops = shops })
    elseif domain == 'factions' then
        -- Delegated to v-factions: it owns the accounts and the audit trail. V.Use keeps
        -- the tab harmless on a server that does not run the module.
        local fac = V.Use('v-factions')
        local rows = {}
        for _, kind in ipairs({ 'job', 'gang' }) do
            for _, r in ipairs(fac.ListFactions(kind) or {}) do rows[#rows + 1] = r end
        end
        resolve({ rows = rows })
    elseif domain == 'jobs' then resolve({ rows = Jobs })
    elseif domain == 'gangs' then resolve({ rows = Gangs })
    elseif domain == 'turfs' then
        -- the owner and the influence live in v-gangs, not here: the turf row is only
        -- the shape on the map
        local st = V.Use('v-gangs').GetState() or {}
        for _, tf in ipairs(Turfs) do
            local o = st[tf.id]
            tf.owner = o and o.owner or nil
            tf.influence = o and o.influence or 0
        end
        local gangs = {}
        for _, g in ipairs(Gangs) do gangs[#gangs + 1] = { name = g.name, label = g.label } end
        resolve({ rows = Turfs, gangs = gangs })
    elseif domain == 'items' then resolve({ rows = Items, categories = Config.ItemCategories, types = Config.ItemTypes })
    elseif domain == 'recipes' then
        -- item names for the pickers (keep the payload light)
        local names = {}
        for _, it in ipairs(Items) do names[#names + 1] = { name = it.name, label = it.label } end
        resolve({ rows = Recipes, items = names, stations = Config.CraftStations })
    elseif domain == 'clothstores' then
        local jobs = {}
        for _, j in ipairs(Jobs) do jobs[#jobs + 1] = { name = j.name, label = j.label } end
        resolve({ rows = ClothStores, jobs = jobs })
    elseif domain == 'garages' then
        local jobs = {}
        for _, j in ipairs(Jobs) do jobs[#jobs + 1] = { name = j.name, label = j.label } end
        resolve({ rows = Garages, jobs = jobs, types = Config.GarageTypes })
    elseif domain == 'uitheme' then
        -- the module list and the presets come from the live registry, so a third-party
        -- script that declared itself is themeable without any change here
        local mods, presets = {}, {}
        if GetResourceState('v-core') == 'started' then
            for name, m in pairs(exports['v-core']:GetModules() or {}) do
                mods[#mods + 1] = { name = name, label = m.label or name }
            end
        end
        table.sort(mods, function(a, b) return a.label < b.label end)
        if GetResourceState('v-ui') == 'started' then
            for _, p in ipairs(exports['v-ui']:GetPresets() or {}) do presets[#presets + 1] = p end
        end
        resolve({ rows = UiThemes, modules = mods, presets = presets })
    elseif domain == 'dealers' then
        local jobs = {}
        for _, j in ipairs(Jobs) do jobs[#jobs + 1] = { name = j.name, label = j.label } end
        resolve({ rows = Dealers, jobs = jobs, cats = Config.VehicleCategories })
    elseif domain == 'rentals' then
        local jobs = {}
        for _, j in ipairs(Jobs) do jobs[#jobs + 1] = { name = j.name, label = j.label } end
        resolve({ rows = Rentals, jobs = jobs, cats = Config.VehicleCategories })
    elseif domain == 'vehcat' then
        local jobs, lics = {}, {}
        for _, j in ipairs(Jobs) do jobs[#jobs + 1] = { name = j.name, label = j.label } end
        for _, l in ipairs(LicTypes) do lics[#lics + 1] = { key = l.key, label = l.label } end
        resolve({ rows = VehCat, jobs = jobs, licenses = lics, cats = Config.VehicleCategories })
    elseif domain == 'licenses' then
        local jobs = {}
        for _, j in ipairs(Jobs) do jobs[#jobs + 1] = { name = j.name, label = j.label } end
        resolve({ rows = LicTypes, jobs = jobs, places = Config.LicensePlaces })
    elseif domain == 'mechshops' then
        local jobs = {}
        for _, j in ipairs(Jobs) do jobs[#jobs + 1] = { name = j.name, label = j.label } end
        resolve({ rows = MechShops, jobs = jobs })
    elseif domain == 'stations' then
        resolve({ rows = Stations, types = Config.FuelTypes })
    elseif domain == 'clothcats' then
        resolve({ rows = ClothCats, kinds = { 'comp', 'prop' }, framings = Config.ClothFramings })
    else resolve(false) end
end)

local function num(v, d) return tonumber(v) or d or 0 end

Core.RegisterCallback('v-world:save', function(source, resolve, data)
    if not isAdmin(source) or type(data) ~= 'table' then resolve(false); return end
    local d, row = data.domain, data.row or {}
    local player = Core.GetPlayer(source)
    local cid = player and player.citizenid or 'console'

    if d == 'blips' then
        local label = tostring(row.label or ''):sub(1, 80)
        if label == '' then resolve({ error = 'label' }); return end
        -- Visibility gate: empty string means "no restriction", stored as NULL.
        local job  = tostring(row.job or ''):sub(1, 50);  if job  == '' then job  = nil end
        local perm = tostring(row.perm or ''):sub(1, 24); if perm == '' then perm = nil end
        local grade = math.max(0, math.floor(num(row.grade)))
        if row.id then
            MySQL.update.await([[UPDATE world_blips SET label=?, sprite=?, color=?, scale=?, x=?, y=?, z=?,
                shortrange=?, enabled=?, job=?, grade=?, perm=? WHERE id=?]],
                { label, num(row.sprite, 1), num(row.color, 0), num(row.scale, 0.8),
                  num(row.x), num(row.y), num(row.z), bool(row.shortrange), bool(row.enabled),
                  job, grade, perm, num(row.id) })
        else
            MySQL.insert.await([[INSERT INTO world_blips (label, sprite, color, scale, x, y, z, shortrange, enabled, job, grade, perm, created_by)
                VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)]],
                { label, num(row.sprite, 1), num(row.color, 0), num(row.scale, 0.8),
                  num(row.x), num(row.y), num(row.z), bool(row.shortrange == nil or row.shortrange),
                  bool(row.enabled == nil or row.enabled), job, grade, perm, cid })
        end

    elseif d == 'shops' then
        local shop = tostring(row.shop or ''):sub(1, 50)
        if shop == '' then resolve({ error = 'shop' }); return end
        local ped = row.ped
        if ped == '' then ped = nil end
        if row.id then
            MySQL.update.await('UPDATE world_shops SET shop=?, x=?, y=?, z=?, h=?, ped=?, blip=?, enabled=? WHERE id=?',
                { shop, num(row.x), num(row.y), num(row.z), num(row.h), ped, bool(row.blip), bool(row.enabled), num(row.id) })
        else
            MySQL.insert.await('INSERT INTO world_shops (shop, x, y, z, h, ped, blip, enabled) VALUES (?,?,?,?,?,?,?,?)',
                { shop, num(row.x), num(row.y), num(row.z), num(row.h), ped,
                  bool(row.blip == nil or row.blip), bool(row.enabled == nil or row.enabled) })
        end

    elseif d == 'factions' then
        -- An ADJUSTMENT, not a balance overwrite: a treasury whose history does not add
        -- up to its balance is indistinguishable from a duplication bug.
        local fac = V.Use('v-factions')
        local name = tostring(row.faction or ''):sub(1, 50)
        local kind = (tostring(row.kind or 'job') == 'gang') and 'gang' or 'job'
        local delta = math.floor(num(row.delta))
        if name == '' then resolve({ error = 'faction' }); return end
        if delta == 0 then resolve({ error = 'amount' }); return end
        local reason = tostring(row.reason or ''):sub(1, 60)
        if reason == '' then reason = 'admin adjustment' end
        local after
        if delta > 0 then after = fac.Deposit(name, kind, delta, reason, cid)
        else after = fac.Withdraw(name, kind, -delta, reason, cid) end
        if after == nil then resolve({ error = 'funds' }); return end

    elseif d == 'gangs' then
        local name = tostring(row.name or ''):lower():gsub('[^%w_]', ''):sub(1, 50)
        if name == '' then resolve({ error = 'name' }); return end
        local grades = {}
        for _, g in ipairs(row.grades or {}) do
            grades[#grades + 1] = { grade = math.floor(num(g.grade)),
                                    name = tostring(g.name or ''):sub(1, 40),
                                    salary = math.floor(num(g.salary)) }
        end
        if #grades == 0 then grades = { { grade = 0, name = 'Member', salary = 0 } } end
        table.sort(grades, function(a, b) return a.grade < b.grade end)
        MySQL.query.await([[INSERT INTO gangs (name, label, type, grades) VALUES (?,?,?,?)
            ON DUPLICATE KEY UPDATE label=VALUES(label), type=VALUES(type), grades=VALUES(grades)]],
            { name, tostring(row.label or name):sub(1, 80),
              tostring(row.type or 'gang'):sub(1, 20), json.encode(grades) })

    elseif d == 'turfs' then
        local tid = tostring(row.id or ''):lower():gsub('[^%w_-]', ''):sub(1, 40)
        if tid == '' then resolve({ error = 'id' }); return end
        local label = tostring(row.label or ''):sub(1, 80)
        if label == '' then resolve({ error = 'label' }); return end
        local radius = math.max(10.0, math.min(500.0, num(row.radius, 90.0)))
        if row.isNew then
            local exists = MySQL.scalar.await('SELECT 1 FROM world_turfs WHERE id = ?', { tid })
            if exists then resolve({ error = 'exists' }); return end
            MySQL.insert.await(
                'INSERT INTO world_turfs (id, label, x, y, z, radius, blip, enabled) VALUES (?,?,?,?,?,?,?,?)',
                { tid, label, num(row.x), num(row.y), num(row.z), radius,
                  bool(row.blip == nil or row.blip), bool(row.enabled == nil or row.enabled) })
        else
            MySQL.update.await(
                'UPDATE world_turfs SET label=?, x=?, y=?, z=?, radius=?, blip=?, enabled=? WHERE id=?',
                { label, num(row.x), num(row.y), num(row.z), radius,
                  bool(row.blip), bool(row.enabled), tid })
        end
        -- An admin can also hand a turf over outright, which is the only way to set an
        -- owner without a capture.
        if row.owner ~= nil then
            V.Use('v-gangs').SetOwner(tid, tostring(row.owner or ''), cid)
        end

    elseif d == 'jobs' then
        local name = tostring(row.name or ''):lower():gsub('[^%w_]', ''):sub(1, 50)
        if name == '' then resolve({ error = 'name' }); return end
        local grades = {}
        for _, g in ipairs(row.grades or {}) do
            grades[#grades + 1] = { grade = math.floor(num(g.grade)), name = tostring(g.name or ''):sub(1, 40), salary = math.floor(num(g.salary)) }
        end
        if #grades == 0 then grades = { { grade = 0, name = 'Employee', salary = 0 } } end
        table.sort(grades, function(a, b) return a.grade < b.grade end)
        MySQL.query.await([[INSERT INTO jobs (name, label, type, grades, whitelisted) VALUES (?,?,?,?,?)
            ON DUPLICATE KEY UPDATE label=VALUES(label), type=VALUES(type), grades=VALUES(grades),
                                    whitelisted=VALUES(whitelisted)]],
            { name, tostring(row.label or name):sub(1, 80), tostring(row.type or 'civ'):sub(1, 20),
              json.encode(grades), bool(row.whitelisted) })
    elseif d == 'items' then
        -- `name` is the primary key referenced by inventories/recipes: it can be set on
        -- CREATE but never changed afterwards (that would orphan every stack). The
        -- display label is freely renameable.
        local name = tostring(row.name or ''):lower():gsub('[^%w_]', ''):sub(1, 50)
        if name == '' then resolve({ error = 'name' }); return end
        local label = tostring(row.label or ''):sub(1, 80)
        if label == '' then resolve({ error = 'label' }); return end
        local meta = json.encode({
            desc   = tostring(row.desc or ''):sub(1, 200),
            type   = tostring(row.itype or 'misc'):sub(1, 24),
            rarity = tostring(row.rarity or 'common'):sub(1, 16),
        })
        local img = row.image
        if img == '' then img = nil end
        if row.isNew then
            local exists = MySQL.scalar.await('SELECT 1 FROM items WHERE name = ?', { name })
            if exists then resolve({ error = 'exists' }); return end
            MySQL.insert.await([[INSERT INTO items (name, label, weight, stackable, usable, category, image, metadata)
                VALUES (?,?,?,?,?,?,?,?)]],
                { name, label, math.floor(num(row.weight, 100)), bool(row.stackable), bool(row.usable),
                  tostring(row.category or 'misc'):sub(1, 30), img, meta })
        else
            MySQL.update.await([[UPDATE items SET label=?, weight=?, stackable=?, usable=?, category=?, image=?, metadata=?
                WHERE name=?]],
                { label, math.floor(num(row.weight, 100)), bool(row.stackable), bool(row.usable),
                  tostring(row.category or 'misc'):sub(1, 30), img, meta, name })
        end

    elseif d == 'clothstores' then
        local label = tostring(row.label or ''):sub(1, 80)
        if label == '' then label = 'Clothing Store' end
        local ped = row.ped;  if ped == '' then ped = nil end
        local job = tostring(row.job or ''):sub(1, 50); if job == '' then job = nil end
        if row.id then
            MySQL.update.await([[UPDATE world_clothing SET label=?, x=?, y=?, z=?, h=?, ped=?, blip=?, job=?, enabled=?
                WHERE id=?]],
                { label, num(row.x), num(row.y), num(row.z), num(row.h), ped,
                  bool(row.blip), job, bool(row.enabled), num(row.id) })
        else
            MySQL.insert.await([[INSERT INTO world_clothing (label, x, y, z, h, ped, blip, job, enabled)
                VALUES (?,?,?,?,?,?,?,?,?)]],
                { label, num(row.x), num(row.y), num(row.z), num(row.h), ped,
                  bool(row.blip == nil or row.blip), job, bool(row.enabled == nil or row.enabled) })
        end

    elseif d == 'garages' then
        -- `id` is stored on every vehicle row (character_vehicles.garage): settable on
        -- CREATE, never changed afterwards or the cars parked there become unreachable.
        local gid = tostring(row.gid or ''):lower():gsub('[^%w_]', ''):sub(1, 40)
        if gid == '' then resolve({ error = 'id' }); return end
        local label = tostring(row.label or ''):sub(1, 80)
        if label == '' then resolve({ error = 'label' }); return end
        local gtype = tostring(row.type or 'public'):sub(1, 12)
        local job = tostring(row.job or ''):sub(1, 50); if job == '' then job = nil end
        if row.isNew then
            local exists = MySQL.scalar.await('SELECT 1 FROM world_garages WHERE id = ?', { gid })
            if exists then resolve({ error = 'exists' }); return end
            MySQL.insert.await([[INSERT INTO world_garages
                (id, label, type, x, y, z, sx, sy, sz, sh, blip, job, fee, enabled) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?)]],
                { gid, label, gtype, num(row.x), num(row.y), num(row.z),
                  num(row.sx), num(row.sy), num(row.sz), num(row.sh),
                  bool(row.blip == nil or row.blip), job, math.max(0, math.floor(num(row.fee))),
                  bool(row.enabled == nil or row.enabled) })
        else
            MySQL.update.await([[UPDATE world_garages SET label=?, type=?, x=?, y=?, z=?, sx=?, sy=?, sz=?, sh=?,
                blip=?, job=?, fee=?, enabled=? WHERE id=?]],
                { label, gtype, num(row.x), num(row.y), num(row.z),
                  num(row.sx), num(row.sy), num(row.sz), num(row.sh),
                  bool(row.blip), job, math.max(0, math.floor(num(row.fee))), bool(row.enabled), gid })
        end

    elseif d == 'uitheme' then
        local mod = tostring(row.module or ''):sub(1, 64)
        if mod == '' then resolve({ error = 'module' }); return end
        -- an empty field means "inherit": store NULL rather than a zero that would read
        -- as a deliberate "fully transparent" or "no roundness"
        local function opt(v)
            if v == nil or v == '' then return nil end
            local n = tonumber(v)
            return n
        end
        local preset = tostring(row.preset or ''); if preset == '' then preset = nil end
        local accent = tostring(row.accent or '')
        if not accent:match('^#%x%x%x%x%x%x$') then accent = nil end

        MySQL.query.await([[INSERT INTO ui_overrides
            (`module`, preset, accent, panel_alpha, backdrop_alpha, radius, motion, font_scale, enabled)
            VALUES (?,?,?,?,?,?,?,?,?)
            ON DUPLICATE KEY UPDATE preset=VALUES(preset), accent=VALUES(accent),
                panel_alpha=VALUES(panel_alpha), backdrop_alpha=VALUES(backdrop_alpha),
                radius=VALUES(radius), motion=VALUES(motion), font_scale=VALUES(font_scale),
                enabled=VALUES(enabled)]],
            { mod, preset, accent, opt(row.panelAlpha), opt(row.backdropAlpha),
              opt(row.radius), opt(row.motion), opt(row.fontScale),
              bool(row.enabled == nil or row.enabled) })

    elseif d == 'dealers' then
        local did = tostring(row.did or ''):lower():gsub('[^%w_]', ''):sub(1, 40)
        if did == '' then resolve({ error = 'id' }); return end
        local label = tostring(row.label or ''):sub(1, 80)
        if label == '' then resolve({ error = 'label' }); return end
        local job = tostring(row.job or ''):sub(1, 50); if job == '' then job = nil end
        -- keep only real categories so a typo cannot hide the whole stock
        local known, keep = {}, {}
        for _, c in ipairs(Config.VehicleCategories or {}) do known[c] = true end
        for c in tostring(row.cats or ''):gmatch('[^,%s]+') do
            if known[c] then keep[#keep + 1] = c end
        end
        if row.isNew then
            local exists = MySQL.scalar.await('SELECT 1 FROM world_dealers WHERE id = ?', { did })
            if exists then resolve({ error = 'exists' }); return end
            MySQL.insert.await([[INSERT INTO world_dealers (id, label, x, y, z, sx, sy, sz, sh, cats, blip, job, enabled)
                VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)]],
                { did, label, num(row.x), num(row.y), num(row.z),
                  num(row.sx), num(row.sy), num(row.sz), num(row.sh), table.concat(keep, ','),
                  bool(row.blip == nil or row.blip), job, bool(row.enabled == nil or row.enabled) })
        else
            MySQL.update.await([[UPDATE world_dealers SET label=?, x=?, y=?, z=?, sx=?, sy=?, sz=?, sh=?,
                cats=?, blip=?, job=?, enabled=? WHERE id=?]],
                { label, num(row.x), num(row.y), num(row.z),
                  num(row.sx), num(row.sy), num(row.sz), num(row.sh), table.concat(keep, ','),
                  bool(row.blip), job, bool(row.enabled), did })
        end

    elseif d == 'rentals' then
        local rid = tostring(row.id or ''):lower():gsub('[^%w_-]', ''):sub(1, 40)
        if rid == '' then resolve({ error = 'id' }); return end
        local label = tostring(row.label or ''):sub(1, 80)
        if label == '' then resolve({ error = 'label' }); return end
        local job = tostring(row.job or ''):sub(1, 50); if job == '' then job = nil end
        local cats = tostring(row.cats or ''):sub(1, 200)
        if row.isNew then
            local exists = MySQL.scalar.await('SELECT 1 FROM world_rentals WHERE id = ?', { rid })
            if exists then resolve({ error = 'exists' }); return end
            MySQL.insert.await([[INSERT INTO world_rentals (id, label, x, y, z, sx, sy, sz, sh, cats, blip, job, enabled)
                VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)]],
                { rid, label, num(row.x), num(row.y), num(row.z),
                  num(row.sx), num(row.sy), num(row.sz), num(row.sh),
                  cats, bool(row.blip == nil or row.blip), job, bool(row.enabled == nil or row.enabled) })
        else
            MySQL.update.await([[UPDATE world_rentals SET label=?, x=?, y=?, z=?, sx=?, sy=?, sz=?, sh=?,
                cats=?, blip=?, job=?, enabled=? WHERE id=?]],
                { label, num(row.x), num(row.y), num(row.z),
                  num(row.sx), num(row.sy), num(row.sz), num(row.sh),
                  cats, bool(row.blip), job, bool(row.enabled), rid })
        end

    elseif d == 'vehcat' then
        -- `model` is the spawn name: settable on CREATE, never after (owned cars store it).
        local model = tostring(row.model or ''):lower():gsub('[^%w_]', ''):sub(1, 50)
        if model == '' then resolve({ error = 'model' }); return end
        local label = tostring(row.label or ''):sub(1, 80)
        if label == '' then resolve({ error = 'label' }); return end
        local lic = tostring(row.license or ''):sub(1, 40); if lic == '' then lic = nil end
        local job = tostring(row.job or ''):sub(1, 50); if job == '' then job = nil end
        local stock = math.floor(num(row.stock, -1))
        -- Blank means "not rentable" (NULL). It must not collapse to 0, which would be a
        -- free hire with no deposit — a very different thing.
        local rdep = (row.rentDeposit ~= nil and tostring(row.rentDeposit) ~= '')
            and math.max(0, math.floor(num(row.rentDeposit))) or nil
        local rfee = (row.rentFee ~= nil and tostring(row.rentFee) ~= '')
            and math.max(0, math.floor(num(row.rentFee))) or nil
        if row.isNew then
            local exists = MySQL.scalar.await('SELECT 1 FROM vehicle_catalogue WHERE model = ?', { model })
            if exists then resolve({ error = 'exists' }); return end
            MySQL.insert.await([[INSERT INTO vehicle_catalogue
                (model, label, cat, price, stock, license, job, enabled, rent_deposit, rent_fee)
                VALUES (?,?,?,?,?,?,?,?,?,?)]],
                { model, label, tostring(row.cat or 'sedans'):sub(1, 30),
                  math.max(0, math.floor(num(row.price))), stock, lic, job,
                  bool(row.enabled == nil or row.enabled), rdep, rfee })
        else
            MySQL.update.await([[UPDATE vehicle_catalogue SET label=?, cat=?, price=?, stock=?, license=?, job=?,
                enabled=?, rent_deposit=?, rent_fee=? WHERE model=?]],
                { label, tostring(row.cat or 'sedans'):sub(1, 30),
                  math.max(0, math.floor(num(row.price))), stock, lic, job,
                  bool(row.enabled), rdep, rfee, model })
        end

    elseif d == 'licenses' then
        -- `key` is stamped on every issued licence: settable on CREATE, never after.
        local key = tostring(row.key or ''):lower():gsub('[^%w_]', ''):sub(1, 40)
        if key == '' then resolve({ error = 'key' }); return end
        local label = tostring(row.label or ''):sub(1, 80)
        if label == '' then resolve({ error = 'label' }); return end
        local issuer = tostring(row.issuer or 'cityhall'):sub(1, 50)
        local price = math.max(0, math.floor(num(row.price)))
        local days = math.max(0, math.floor(num(row.days)))
        if row.isNew then
            local exists = MySQL.scalar.await('SELECT 1 FROM license_types WHERE `key` = ?', { key })
            if exists then resolve({ error = 'exists' }); return end
            MySQL.insert.await([[INSERT INTO license_types (`key`, label, issuer, price, days, test, sort, enabled)
                VALUES (?,?,?,?,?,?,?,?)]],
                { key, label, issuer, price, days, bool(row.test), math.floor(num(row.sort)),
                  bool(row.enabled == nil or row.enabled) })
        else
            MySQL.update.await([[UPDATE license_types SET label=?, issuer=?, price=?, days=?, test=?, sort=?, enabled=?
                WHERE `key`=?]],
                { label, issuer, price, days, bool(row.test), math.floor(num(row.sort)),
                  bool(row.enabled), key })
        end

    elseif d == 'mechshops' then
        local mid = tostring(row.mid or ''):lower():gsub('[^%w_]', ''):sub(1, 40)
        if mid == '' then resolve({ error = 'id' }); return end
        local label = tostring(row.label or ''):sub(1, 80)
        if label == '' then resolve({ error = 'label' }); return end
        local job = tostring(row.job or ''):sub(1, 50); if job == '' then job = nil end
        local mult = math.max(0.1, math.min(5.0, tonumber(row.mult) or 1.0))
        if row.isNew then
            local exists = MySQL.scalar.await('SELECT 1 FROM world_mechshops WHERE id = ?', { mid })
            if exists then resolve({ error = 'exists' }); return end
            MySQL.insert.await([[INSERT INTO world_mechshops (id, label, x, y, z, blip, job, mult, enabled)
                VALUES (?,?,?,?,?,?,?,?,?)]],
                { mid, label, num(row.x), num(row.y), num(row.z),
                  bool(row.blip == nil or row.blip), job, mult, bool(row.enabled == nil or row.enabled) })
        else
            MySQL.update.await([[UPDATE world_mechshops SET label=?, x=?, y=?, z=?, blip=?, job=?, mult=?, enabled=?
                WHERE id=?]],
                { label, num(row.x), num(row.y), num(row.z), bool(row.blip), job, mult, bool(row.enabled), mid })
        end

    elseif d == 'stations' then
        local sid = tostring(row.sid or ''):lower():gsub('[^%w_]', ''):sub(1, 40)
        if sid == '' then resolve({ error = 'id' }); return end
        local label = tostring(row.label or ''):sub(1, 80)
        if label == '' then resolve({ error = 'label' }); return end
        -- keep only known fuel keys, so a typo can't create a pump nobody can use
        local known, keep = {}, {}
        for _, k in ipairs(Config.FuelTypes or {}) do known[k] = true end
        for k in tostring(row.types or ''):gmatch('[^,%s]+') do
            if known[k] then keep[#keep + 1] = k end
        end
        if #keep == 0 then resolve({ error = 'types' }); return end
        local mult = math.max(0.1, math.min(5.0, tonumber(row.mult) or 1.0))
        if row.isNew then
            local exists = MySQL.scalar.await('SELECT 1 FROM world_stations WHERE id = ?', { sid })
            if exists then resolve({ error = 'exists' }); return end
            MySQL.insert.await([[INSERT INTO world_stations (id, label, x, y, z, types, mult, blip, enabled)
                VALUES (?,?,?,?,?,?,?,?,?)]],
                { sid, label, num(row.x), num(row.y), num(row.z), table.concat(keep, ','), mult,
                  bool(row.blip == nil or row.blip), bool(row.enabled == nil or row.enabled) })
        else
            MySQL.update.await([[UPDATE world_stations SET label=?, x=?, y=?, z=?, types=?, mult=?, blip=?, enabled=?
                WHERE id=?]],
                { label, num(row.x), num(row.y), num(row.z), table.concat(keep, ','), mult,
                  bool(row.blip), bool(row.enabled), sid })
        end

    elseif d == 'clothcats' then
        -- `key` is referenced by every worn-clothing metadata blob: settable on CREATE,
        -- never changed afterwards (that would orphan every garment already owned).
        local key = tostring(row.key or ''):lower():gsub('[^%w_]', ''):sub(1, 30)
        if key == '' then resolve({ error = 'key' }); return end
        local label = tostring(row.label or ''):sub(1, 60)
        if label == '' then resolve({ error = 'label' }); return end
        local kind = (row.kind == 'prop') and 'prop' or 'comp'
        local slot = math.max(0, math.floor(num(row.slot)))
        -- a slot that doesn't exist on a ped would silently render nothing
        local maxSlot = (kind == 'prop') and 7 or 11
        if slot > maxSlot then resolve({ error = 'slot' }); return end
        local item = tostring(row.item or ''):lower():gsub('[^%w_]', ''):sub(1, 50)
        if item == '' then item = key end
        local framing = tostring(row.framing or 'body'):sub(1, 10)
        if row.isNew then
            local exists = MySQL.scalar.await('SELECT 1 FROM clothing_categories WHERE `key` = ?', { key })
            if exists then resolve({ error = 'exists' }); return end
            MySQL.insert.await([[INSERT INTO clothing_categories
                (`key`, label, kind, slot, item, price, framing, sort, enabled) VALUES (?,?,?,?,?,?,?,?,?)]],
                { key, label, kind, slot, item, math.max(0, math.floor(num(row.price))), framing,
                  math.floor(num(row.sort)), bool(row.enabled == nil or row.enabled) })
        else
            MySQL.update.await([[UPDATE clothing_categories SET label=?, kind=?, slot=?, item=?, price=?,
                framing=?, sort=?, enabled=? WHERE `key`=?]],
                { label, kind, slot, item, math.max(0, math.floor(num(row.price))), framing,
                  math.floor(num(row.sort)), bool(row.enabled), key })
        end

    elseif d == 'recipes' then
        local station = tostring(row.station or ''):sub(1, 40)
        local output  = tostring(row.output or ''):sub(1, 60)
        if station == '' or output == '' then resolve({ error = 'field' }); return end
        local inputs = {}
        for _, ing in ipairs(row.inputs or {}) do
            local n = tostring(ing.item or '')
            local q = math.floor(num(ing.qty, 1))
            if n ~= '' and q > 0 then inputs[n] = q end
        end
        if next(inputs) == nil then resolve({ error = 'inputs' }); return end
        if row.id then
            MySQL.update.await('UPDATE craft_recipes SET station=?, output=?, count=?, time=?, inputs=?, enabled=? WHERE id=?',
                { station, output, math.max(1, math.floor(num(row.count, 1))), math.max(500, math.floor(num(row.time, 3000))),
                  json.encode(inputs), bool(row.enabled), num(row.id) })
        else
            MySQL.insert.await('INSERT INTO craft_recipes (station, output, count, time, inputs, enabled) VALUES (?,?,?,?,?,?)',
                { station, output, math.max(1, math.floor(num(row.count, 1))), math.max(500, math.floor(num(row.time, 3000))),
                  json.encode(inputs), bool(row.enabled == nil or row.enabled) })
        end
    else
        resolve(false); return
    end

    reload(d); broadcast(d)
    Core.Log('world', ('%s saved %s'):format(cid, d), nil, cid ~= 'console' and cid or nil)
    resolve({ ok = true })
end)

Core.RegisterCallback('v-world:delete', function(source, resolve, data)
    if not isAdmin(source) or type(data) ~= 'table' then resolve(false); return end
    local d, id = data.domain, data.id
    if d == 'blips' then MySQL.query.await('DELETE FROM world_blips WHERE id = ?', { num(id) })
    elseif d == 'shops' then MySQL.query.await('DELETE FROM world_shops WHERE id = ?', { num(id) })
    elseif d == 'gangs' then
        local name = tostring(id or '')
        if name == '' then resolve({ error = 'protected' }); return end
        -- members would keep a gang name pointing at nothing
        local used = MySQL.scalar.await('SELECT 1 FROM characters WHERE gang = ? LIMIT 1', { name })
        if used then resolve({ error = 'inuse' }); return end
        MySQL.query.await('DELETE FROM gangs WHERE name = ?', { name })
    elseif d == 'turfs' then
        local tid = tostring(id or '')
        if tid == '' then resolve({ error = 'protected' }); return end
        MySQL.query.await('DELETE FROM world_turfs WHERE id = ?', { tid })
    elseif d == 'jobs' then
        local name = tostring(id or '')
        if name == '' or name == 'unemployed' then resolve({ error = 'protected' }); return end
        MySQL.query.await('DELETE FROM jobs WHERE name = ?', { name })
    elseif d == 'items' then
        local name = tostring(id or '')
        if name == '' or name == 'money' then resolve({ error = 'protected' }); return end
        -- refuse while the item is still referenced by a recipe (input or output)
        local used = MySQL.scalar.await(
            "SELECT 1 FROM craft_recipes WHERE output = ? OR JSON_CONTAINS_PATH(inputs, 'one', CONCAT('$.\"', ?, '\"')) LIMIT 1",
            { name, name })
        if used then resolve({ error = 'inuse' }); return end
        MySQL.query.await('DELETE FROM items WHERE name = ?', { name })
    elseif d == 'clothstores' then
        MySQL.query.await('DELETE FROM world_clothing WHERE id = ?', { num(id) })
    elseif d == 'garages' then
        local gid = tostring(id or '')
        if gid == '' then resolve({ error = 'protected' }); return end
        -- refuse while cars are still parked there: they would become unreachable
        local parked = MySQL.scalar.await('SELECT 1 FROM character_vehicles WHERE garage = ? LIMIT 1', { gid })
        if parked then resolve({ error = 'inuse' }); return end
        MySQL.query.await('DELETE FROM world_garages WHERE id = ?', { gid })
    elseif d == 'uitheme' then
        local mod = tostring(id or '')
        if mod == '' then resolve({ error = 'protected' }); return end
        MySQL.query.await('DELETE FROM ui_overrides WHERE `module` = ?', { mod })
    elseif d == 'dealers' then
        local did = tostring(id or '')
        if did == '' then resolve({ error = 'protected' }); return end
        MySQL.query.await('DELETE FROM world_dealers WHERE id = ?', { did })
    elseif d == 'rentals' then
        local rid = tostring(id or '')
        if rid == '' then resolve({ error = 'protected' }); return end
        MySQL.query.await('DELETE FROM world_rentals WHERE id = ?', { rid })
    elseif d == 'vehcat' then
        local model = tostring(id or '')
        if model == '' then resolve({ error = 'protected' }); return end
        -- a model somebody already owns stays in the catalogue: the row is what a garage,
        -- a repair and a resale all read the label and price from
        local owned = MySQL.scalar.await('SELECT 1 FROM character_vehicles WHERE model = ? LIMIT 1', { model })
        if owned then resolve({ error = 'inuse' }); return end
        MySQL.query.await('DELETE FROM vehicle_catalogue WHERE model = ?', { model })
    elseif d == 'licenses' then
        local key = tostring(id or '')
        if key == '' then resolve({ error = 'protected' }); return end
        -- refuse while characters still hold it: deleting the type would strand them
        local held = MySQL.scalar.await('SELECT 1 FROM character_licenses WHERE type = ? LIMIT 1', { key })
        if held then resolve({ error = 'inuse' }); return end
        MySQL.query.await('DELETE FROM license_types WHERE `key` = ?', { key })
    elseif d == 'mechshops' then
        local mid = tostring(id or '')
        if mid == '' then resolve({ error = 'protected' }); return end
        MySQL.query.await('DELETE FROM world_mechshops WHERE id = ?', { mid })
    elseif d == 'stations' then
        local sid = tostring(id or '')
        if sid == '' then resolve({ error = 'protected' }); return end
        MySQL.query.await('DELETE FROM world_stations WHERE id = ?', { sid })
    elseif d == 'clothcats' then
        local key = tostring(id or '')
        if key == '' then resolve({ error = 'protected' }); return end
        MySQL.query.await('DELETE FROM clothing_categories WHERE `key` = ?', { key })
    elseif d == 'recipes' then
        MySQL.query.await('DELETE FROM craft_recipes WHERE id = ?', { num(id) })
    else resolve(false); return end

    reload(d); broadcast(d)
    local player = Core.GetPlayer(source)
    Core.Log('world', ('%s deleted %s #%s'):format(player and player.citizenid or 'console', d, tostring(id)),
        nil, player and player.citizenid or nil)
    resolve({ ok = true })
end)

-- A joining client asks for the current blips once it is ready.
RegisterNetEvent('v-world:server:request', function()
    pushBlips(source)
end)
