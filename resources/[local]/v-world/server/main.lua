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
local ClothStores, ClothCats = {}, {}
local Garages = {}
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

local function reload(domain)
    if domain == 'blips'   or not domain then loadBlips() end
    if domain == 'shops'   or not domain then loadShops() end
    if domain == 'jobs'    or not domain then loadJobs() end
    if domain == 'items'   or not domain then loadItems() end
    if domain == 'recipes' or not domain then loadRecipes() end
    if domain == 'clothstores' or not domain then loadClothStores() end
    if domain == 'clothcats'   or not domain then loadClothCats() end
    if domain == 'garages'     or not domain then loadGarages() end
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
exports('GetBlips', function() return Blips end)
exports('GetShopLocations', function() return ShopLocs end)
exports('GetJobs', function() return Jobs end)
exports('GetItems', function() return Items end)
exports('GetRecipes', function() return Recipes end)
exports('GetClothStores', function() return ClothStores end)
exports('GetClothCategories', function() return ClothCats end)
exports('GetGarages', function() return Garages end)

-- v-crafting: list of { station, output, count, time, inputs = { item = qty } }
exports('SeedRecipes', function(defaults)
    if not ready or type(defaults) ~= 'table' then return false end
    if #Recipes > 0 then return false end
    for _, r in ipairs(defaults) do
        MySQL.insert.await(
            'INSERT INTO craft_recipes (station, output, count, time, inputs, enabled) VALUES (?,?,?,?,?,1)',
            { r.station, r.output, r.count or 1, r.time or 3000, json.encode(r.inputs or {}) })
    end
    loadRecipes()
    print(('[v-world] seeded %d craft recipe(s) from config'):format(#Recipes))
    return true
end)

-- ── Seeding (called ONCE by the owning module at boot, only if empty) ──
-- v-shops: list of { shop, x, y, z, h, ped, blip }
exports('SeedShopLocations', function(defaults)
    if not ready or type(defaults) ~= 'table' then return false end
    if #ShopLocs > 0 then return false end                       -- already managed in DB
    for _, l in ipairs(defaults) do
        MySQL.insert.await(
            'INSERT INTO world_shops (shop, x, y, z, h, ped, blip, enabled) VALUES (?,?,?,?,?,?,?,1)',
            { l.shop, l.x, l.y, l.z, l.h or 0.0, l.ped, bool(l.blip == nil or l.blip) })
    end
    loadShops()
    print(('[v-world] seeded %d shop location(s) from config'):format(#ShopLocs))
    return true
end)

-- v-jobs: map jobId -> { label, grades = { [n] = { name, salary } } }
-- v-clothing: list of { x, y, z, h, label?, ped? }
exports('SeedClothStores', function(defaults)
    if not ready or type(defaults) ~= 'table' then return false end
    if #ClothStores > 0 then return false end
    for _, l in ipairs(defaults) do
        MySQL.insert.await('INSERT INTO world_clothing (label, x, y, z, h, ped, blip, enabled) VALUES (?,?,?,?,?,?,1,1)',
            { l.label or 'Clothing Store', l.x, l.y, l.z, l.h or 0.0, l.ped })
    end
    loadClothStores()
    print(('[v-world] seeded %d clothing store(s) from config'):format(#ClothStores))
    return true
end)

-- v-clothing: list of { key, label, kind, slot, item, price, framing, sort }
exports('SeedClothCategories', function(defaults)
    if not ready or type(defaults) ~= 'table' then return false end
    if #ClothCats > 0 then return false end
    for i, c in ipairs(defaults) do
        MySQL.insert.await([[INSERT IGNORE INTO clothing_categories
            (`key`, label, kind, slot, item, price, framing, sort, enabled) VALUES (?,?,?,?,?,?,?,?,1)]],
            { c.key, c.label or c.key, c.kind or 'comp', c.slot or c.id or 0, c.item or c.key,
              c.price or 0, c.framing or 'body', c.sort or i })
    end
    loadClothCats()
    print(('[v-world] seeded %d clothing category(ies) from config'):format(#ClothCats))
    return true
end)

-- v-garages: list of { id, label, type, x, y, z, sx, sy, sz, sh, job, fee }
exports('SeedGarages', function(defaults)
    if not ready or type(defaults) ~= 'table' then return false end
    if #Garages > 0 then return false end
    for _, g in ipairs(defaults) do
        MySQL.insert.await([[INSERT IGNORE INTO world_garages
            (id, label, type, x, y, z, sx, sy, sz, sh, blip, job, fee, enabled) VALUES (?,?,?,?,?,?,?,?,?,?,1,?,?,1)]],
            { g.id, g.label or g.id, g.type or 'public', g.x, g.y, g.z,
              g.sx, g.sy, g.sz, g.sh or 0.0, g.job, g.fee or 0 })
    end
    loadGarages()
    print(('[v-world] seeded %d garage(s) from config'):format(#Garages))
    return true
end)

exports('SeedJobs', function(defaults)
    if not ready or type(defaults) ~= 'table' then return false end
    if #Jobs > 0 then return false end
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
    elseif domain == 'jobs' then resolve({ rows = Jobs })
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
