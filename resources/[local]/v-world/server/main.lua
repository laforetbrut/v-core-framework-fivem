-- v-world | server
-- Single owner of the admin-editable world content:
--   * world_blips  — free-form map blips
--   * world_shops  — shop/store locations (v-shops consumes them)
--   * jobs         — jobs + grades + salaries (v-jobs consumes them)
--
-- Each domain is SEEDED from the owning module's static config the first time the
-- table is empty, so behaviour is identical to the hardcoded setup until an admin
-- edits something. Every mutation reloads the cache, notifies the owning modules
-- (`v-world:server:changed`) and pushes a live sync to clients — no restart.
local Core = exports['v-core']:GetCore()

local Blips, ShopLocs, Jobs = {}, {}, {}
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
        `created_by` VARCHAR(24) DEFAULT NULL,
        PRIMARY KEY (`id`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])

    MySQL.query.await([[CREATE TABLE IF NOT EXISTS `world_shops` (
        `id` INT NOT NULL AUTO_INCREMENT,
        `shop` VARCHAR(50) NOT NULL,
        `x` FLOAT NOT NULL, `y` FLOAT NOT NULL, `z` FLOAT NOT NULL, `h` FLOAT NOT NULL DEFAULT 0,
        `ped` VARCHAR(60) DEFAULT NULL,
        `blip` TINYINT(1) NOT NULL DEFAULT 1,
        `enabled` TINYINT(1) NOT NULL DEFAULT 1,
        PRIMARY KEY (`id`), KEY `shop_idx` (`shop`)
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
        Jobs[#Jobs + 1] = r
    end
end

local function reload(domain)
    if domain == 'blips' or not domain then loadBlips() end
    if domain == 'shops' or not domain then loadShops() end
    if domain == 'jobs'  or not domain then loadJobs() end
end

-- Push blips to clients and tell the owning modules to re-read their data.
local function broadcast(domain)
    if domain == 'blips' or not domain then
        TriggerClientEvent('v-world:client:blips', -1, Blips)
    end
    TriggerEvent('v-world:server:changed', domain)
end

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
exports('SeedJobs', function(defaults)
    if not ready or type(defaults) ~= 'table' then return false end
    if #Jobs > 0 then return false end
    for name, j in pairs(defaults) do
        local arr = {}
        for n, g in pairs(j.grades or {}) do
            arr[#arr + 1] = { grade = n, name = g.name or ('Grade ' .. n), salary = g.salary or 0 }
        end
        table.sort(arr, function(a, b) return a.grade < b.grade end)
        MySQL.insert.await('INSERT IGNORE INTO jobs (name, label, type, grades) VALUES (?,?,?,?)',
            { name, j.label or name, j.type or 'civ', json.encode(arr) })
    end
    loadJobs()
    print(('[v-world] seeded %d job(s) from config'):format(#Jobs))
    return true
end)

-- ── Admin CRUD (permission verified server-side on every call) ──
Core.RegisterCallback('v-world:list', function(source, resolve, domain)
    if not isAdmin(source) then resolve(false); return end
    if domain == 'blips' then resolve({ rows = Blips, presets = Config.BlipPresets, colors = Config.BlipColors })
    elseif domain == 'shops' then
        local shops = MySQL.query.await('SELECT id, label FROM shops ORDER BY id') or {}
        resolve({ rows = ShopLocs, shops = shops })
    elseif domain == 'jobs' then resolve({ rows = Jobs })
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
        if row.id then
            MySQL.update.await([[UPDATE world_blips SET label=?, sprite=?, color=?, scale=?, x=?, y=?, z=?,
                shortrange=?, enabled=? WHERE id=?]],
                { label, num(row.sprite, 1), num(row.color, 0), num(row.scale, 0.8),
                  num(row.x), num(row.y), num(row.z), bool(row.shortrange), bool(row.enabled), num(row.id) })
        else
            MySQL.insert.await([[INSERT INTO world_blips (label, sprite, color, scale, x, y, z, shortrange, enabled, created_by)
                VALUES (?,?,?,?,?,?,?,?,?,?)]],
                { label, num(row.sprite, 1), num(row.color, 0), num(row.scale, 0.8),
                  num(row.x), num(row.y), num(row.z), bool(row.shortrange == nil or row.shortrange),
                  bool(row.enabled == nil or row.enabled), cid })
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
        MySQL.query.await([[INSERT INTO jobs (name, label, type, grades) VALUES (?,?,?,?)
            ON DUPLICATE KEY UPDATE label=VALUES(label), type=VALUES(type), grades=VALUES(grades)]],
            { name, tostring(row.label or name):sub(1, 80), tostring(row.type or 'civ'):sub(1, 20), json.encode(grades) })
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
    else resolve(false); return end

    reload(d); broadcast(d)
    local player = Core.GetPlayer(source)
    Core.Log('world', ('%s deleted %s #%s'):format(player and player.citizenid or 'console', d, tostring(id)),
        nil, player and player.citizenid or nil)
    resolve({ ok = true })
end)

-- A joining client asks for the current blips once it is ready.
RegisterNetEvent('v-world:server:request', function()
    TriggerClientEvent('v-world:client:blips', source, Blips)
end)
