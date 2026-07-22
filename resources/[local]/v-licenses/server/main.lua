-- v-licenses | server
-- The single source of truth for what a CHARACTER is legally allowed to do.
--
-- Three permission concepts exist in this framework and they are not interchangeable:
--   v-core permission  -> staff (who may use the admin panel)
--   v-jobs job/grade    -> employment (who is on the payroll)
--   a licence           -> the law (what this character may legally do)
-- Anything gating a real-world capability asks HERE and nowhere else.
local Core = exports['v-core']:GetCore()

local Types = Config.Types          -- runtime list (DB, or config fallback)
local Held  = {}                    -- citizenid -> { type = row } (cache for online players)

local S = Config.Status

-- ── Types ──────────────────────────────────────────────────────
local function rebuildTypes()
    local rows = (GetResourceState('v-world') == 'started' and exports['v-world']:IsReady())
        and exports['v-world']:GetLicenseTypes() or nil
    local list = {}
    for _, r in ipairs(rows or {}) do
        if r.enabled == 1 then
            list[#list + 1] = { key = r.key, i18n = 'lic.' .. r.key, label = r.label,
                                issuer = r.issuer, price = r.price, days = r.days,
                                test = r.test == 1 }
        end
    end
    if #list == 0 then list = Config.Types end
    Types = list
    TriggerClientEvent('v-licenses:client:types', -1, Types)
end

local function typeByKey(key)
    for _, t in ipairs(Types) do if t.key == key then return t end end
end

-- ── Reading ────────────────────────────────────────────────────
local function loadHeld(citizenid)
    local out = {}
    for _, r in ipairs(MySQL.query.await(
        'SELECT type, status, points, issued_at, expires_at, issuer FROM character_licenses WHERE citizenid = ?',
        { citizenid }) or {}) do
        out[r.type] = r
    end
    Held[citizenid] = out
    return out
end

local function held(citizenid)
    return Held[citizenid] or loadHeld(citizenid)
end

--- Expire anything past its date, lazily. A licence that lapsed while the player was
--- offline must not still read as valid the moment they log in.
local function freshen(citizenid)
    local rows = held(citizenid)
    local now = os.time()
    for key, r in pairs(rows) do
        if r.status == S.valid and r.expires_at then
            local exp = type(r.expires_at) == 'number' and r.expires_at or nil
            if not exp then
                -- oxmysql hands back a string for TIMESTAMP; compare in SQL instead
                local lapsed = MySQL.scalar.await(
                    'SELECT 1 FROM character_licenses WHERE citizenid = ? AND type = ? AND expires_at IS NOT NULL AND expires_at < NOW()',
                    { citizenid, key })
                if lapsed then
                    r.status = S.expired
                    MySQL.update.await('UPDATE character_licenses SET status = ? WHERE citizenid = ? AND type = ?',
                        { S.expired, citizenid, key })
                end
            elseif exp < now then
                r.status = S.expired
                MySQL.update.await('UPDATE character_licenses SET status = ? WHERE citizenid = ? AND type = ?',
                    { S.expired, citizenid, key })
            end
        end
    end
    return rows
end

local function cidOf(src)
    local p = Core.GetPlayer(src)
    return p and p.citizenid or nil
end

--- The one question everything else asks.
local function hasLicense(src, key)
    local cid = cidOf(src)
    if not cid or not key then return false end
    local r = freshen(cid)[key]
    return (r ~= nil) and r.status == S.valid
end

-- ── Writing ────────────────────────────────────────────────────
--- Grant (or renew) a licence. `issuer` is recorded for the audit trail.
local function grant(citizenid, key, issuer)
    local t = typeByKey(key)
    if not citizenid or not t then return false, 'unknown' end
    local expires = (t.days and t.days > 0)
        and ('DATE_ADD(NOW(), INTERVAL %d DAY)'):format(math.floor(t.days)) or 'NULL'
    MySQL.query.await(([[INSERT INTO character_licenses (citizenid, type, status, points, issued_at, expires_at, issuer)
        VALUES (?, ?, ?, 0, NOW(), %s, ?)
        ON DUPLICATE KEY UPDATE status = VALUES(status), points = 0,
                                issued_at = NOW(), expires_at = VALUES(expires_at), issuer = VALUES(issuer)]]):format(expires),
        { citizenid, key, S.valid, issuer })
    loadHeld(citizenid)
    return true
end

local function setStatus(citizenid, key, status)
    if not citizenid or not typeByKey(key) then return false end
    MySQL.update.await('UPDATE character_licenses SET status = ? WHERE citizenid = ? AND type = ?',
        { status, citizenid, key })
    loadHeld(citizenid)
    return true
end

--- Add demerit points; reaching the limit suspends the licence automatically.
local function addPoints(citizenid, key, n)
    local r = held(citizenid)[key]
    if not r then return false, 'nolicense' end
    local pts = math.max(0, (tonumber(r.points) or 0) + (tonumber(n) or 0))
    local status = r.status
    if pts >= Config.Points.limit and status == S.valid then status = S.suspended end
    MySQL.update.await('UPDATE character_licenses SET points = ?, status = ? WHERE citizenid = ? AND type = ?',
        { pts, status, citizenid, key })
    loadHeld(citizenid)
    return true, pts, status
end

-- ── Exports (the surface every other module uses) ──
exports('Has',        function(src, key) return hasLicense(src, key) end)
exports('HasByCid',   function(cid, key)
    local r = cid and freshen(cid)[key]
    return (r ~= nil) and r.status == S.valid
end)
exports('Get',        function(src)
    local cid = cidOf(src)
    return cid and freshen(cid) or {}
end)
exports('GetTypes',   function() return Types end)
exports('Grant',      function(cid, key, issuer) return grant(cid, key, issuer or 'admin') end)
exports('Revoke',     function(cid, key) return setStatus(cid, key, S.revoked) end)
exports('Suspend',    function(cid, key) return setStatus(cid, key, S.suspended) end)
exports('Reinstate',  function(cid, key) return setStatus(cid, key, S.valid) end)
exports('AddPoints',  function(cid, key, n) return addPoints(cid, key, n) end)
--- Which licence a vehicle class needs to be bought/driven legally.
exports('LicenseForClass', function(class)
    return Config.VehicleClassLicense[tonumber(class) or -1] or Config.DefaultVehicleLicense
end)

-- ── Player-facing: read my own wallet ──────────────────────────
Core.RegisterCallback('v-licenses:mine', function(source, resolve)
    local p = Core.GetPlayer(source)
    if not p then resolve(false); return end
    local rows = freshen(p.citizenid)
    local out = {}
    for _, t in ipairs(Types) do
        local r = rows[t.key]
        out[#out + 1] = {
            key = t.key, i18n = t.i18n, label = t.label, issuer = t.issuer,
            price = t.price, days = t.days, test = t.test,
            status = r and r.status or nil,
            points = r and r.points or 0,
            expires = r and r.expires_at or nil,
        }
    end
    resolve({ licenses = out, pointLimit = Config.Points.limit, cash = p.money.cash, bank = p.money.bank })
end)

-- ── Issuing ────────────────────────────────────────────────────
--- May `src` issue `type` to someone? A place-issuer (`cityhall`, `school`) serves anyone
--- standing there — the place itself is the authority. Anything else is a JOB, so an
--- on-duty member of that job is the authority, which is how a weapon permit becomes a
--- police decision rather than a shop transaction.
local function mayIssue(src, t)
    if not t then return false, 'unknown' end
    if Config.PlaceIssuers[t.issuer] then return true end
    local p = Core.GetPlayer(src)
    local job = p and p.job                       -- { name, grade }
    if not job or job.name ~= t.issuer then return false, 'notissuer' end
    if GetResourceState('v-jobs') == 'started' and not exports['v-jobs']:IsOnDuty(src) then
        return false, 'offduty'
    end
    return true
end

--- Buy a licence for yourself at a place that issues it (city hall, driving school).
Core.RegisterCallback('v-licenses:buy', function(source, resolve, data)
    local p = Core.GetPlayer(source)
    local key = type(data) == 'table' and tostring(data.type or '') or ''
    local t = typeByKey(key)
    if not p or not t then resolve({ error = 'unknown' }); return end
    if not Config.PlaceIssuers[t.issuer] then resolve({ error = 'notissuer' }); return end

    local rows = freshen(p.citizenid)
    local cur = rows[key]
    if cur and cur.status == S.valid then resolve({ error = 'already' }); return end
    if cur and cur.status == S.revoked then resolve({ error = 'revoked' }); return end
    -- a licence that needs a test can only be renewed here, never issued from nothing
    if t.test and not cur then resolve({ error = 'needtest' }); return end

    local account = (data.account == 'bank') and 'bank' or 'cash'
    local price = math.max(0, math.floor(tonumber(t.price) or 0))
    if price > 0 and not p.RemoveMoney(account, price, 'license-' .. key) then
        resolve({ error = 'funds' }); return
    end
    if not grant(p.citizenid, key, t.issuer) then
        if price > 0 then p.AddMoney(account, price, 'license-refund') end
        resolve({ error = 'unknown' }); return
    end
    Core.Log('licenses', ('%s obtained the %s licence for %d'):format(p.citizenid, key, price), nil, p.citizenid)
    Core.Notify(source, LP(source, 'lic.got', LP(source, t.i18n)), 'success')
    local p2 = Core.GetPlayer(source)
    resolve({ ok = true, cash = p2.money.cash, bank = p2.money.bank })
end)

--- Issue a licence to a nearby player. Used by the driving school (test passed), the PD
--- (weapon permit) and any job that issues its own paperwork.
Core.RegisterCallback('v-licenses:issue', function(source, resolve, data)
    local p = Core.GetPlayer(source)
    local key = type(data) == 'table' and tostring(data.type or '') or ''
    local target = type(data) == 'table' and tonumber(data.target) or nil
    local t = typeByKey(key)
    if not p or not t or not target then resolve(false); return end

    local ok, why = mayIssue(source, t)
    if not ok then resolve({ error = why }); return end

    -- proximity re-derived from the server-owned peds, never taken from the client
    local a, b = GetPlayerPed(source), GetPlayerPed(target)
    if not a or not b or a == 0 or b == 0 then resolve({ error = 'gone' }); return end
    if #(GetEntityCoords(a) - GetEntityCoords(b)) > 5.0 then resolve({ error = 'far' }); return end

    local tp = Core.GetPlayer(target)
    if not tp then resolve({ error = 'gone' }); return end
    if not grant(tp.citizenid, key, p.citizenid) then resolve({ error = 'unknown' }); return end

    Core.Log('licenses', ('%s issued the %s licence to %s'):format(p.citizenid, key, tp.citizenid),
        nil, p.citizenid)
    Core.Notify(target, LP(target, 'lic.got', LP(target, t.i18n)), 'success')
    Core.Notify(source, LP(source, 'lic.issued'), 'success')
    resolve({ ok = true })
end)

--- Take a licence away. Same authority rule, plus staff can always do it.
Core.RegisterCallback('v-licenses:revoke', function(source, resolve, data)
    local p = Core.GetPlayer(source)
    local key = type(data) == 'table' and tostring(data.type or '') or ''
    local target = type(data) == 'table' and tonumber(data.target) or nil
    local t = typeByKey(key)
    if not p or not t or not target then resolve(false); return end

    local staff = Core.HasPermission(source, 'admin')
    if not staff then
        local ok, why = mayIssue(source, t)
        if not ok then resolve({ error = why }); return end
        local a, b = GetPlayerPed(source), GetPlayerPed(target)
        if not a or not b or a == 0 or b == 0 then resolve({ error = 'gone' }); return end
        if #(GetEntityCoords(a) - GetEntityCoords(b)) > 5.0 then resolve({ error = 'far' }); return end
    end

    local tp = Core.GetPlayer(target)
    if not tp then resolve({ error = 'gone' }); return end
    local suspend = data.suspend and true or false
    setStatus(tp.citizenid, key, suspend and S.suspended or S.revoked)

    Core.Log('licenses', ('%s %s the %s licence of %s'):format(
        p.citizenid, suspend and 'suspended' or 'revoked', key, tp.citizenid), nil, p.citizenid)
    Core.Notify(target, LP(target, suspend and 'lic.suspended' or 'lic.revoked', LP(target, t.i18n)), 'error')
    resolve({ ok = true })
end)

-- ── Lifecycle ──────────────────────────────────────────────────
-- Warm the cache on login so the first `Has()` of the session isn't a query.
AddEventHandler('v-core:server:onPlayerLoaded', function(_, player)
    if player and player.citizenid then loadHeld(player.citizenid) end
end)

AddEventHandler('playerDropped', function()
    local p = Core.GetPlayer(source)
    if p then Held[p.citizenid] = nil end
end)

CreateThread(function()
    while GetResourceState('oxmysql') ~= 'started' do Wait(100) end
    local tries = 0
    while GetResourceState('v-world') == 'started' and not exports['v-world']:IsReady() and tries < 100 do
        Wait(100); tries = tries + 1
    end
    if GetResourceState('v-world') == 'started' and exports['v-world']:IsReady() then
        -- the config carries i18n keys; the DB wants a human label
        local seed = {}
        for _, t in ipairs(Config.Types) do
            seed[#seed + 1] = { key = t.key, label = t.key, issuer = t.issuer, price = t.price,
                                days = t.days, test = t.test, sort = t.sort }
        end
        exports['v-world']:SeedLicenseTypes(seed)
    end
    rebuildTypes()
    declareSettings()
    applySettings()
end)

AddEventHandler('v-world:server:changed', function(domain)
    if domain == nil or domain == 'licenses' then rebuildTypes() end
end)

RegisterNetEvent('v-licenses:server:request', function()
    TriggerClientEvent('v-licenses:client:types', source, Types)
end)

-- ── Admin-tunable settings ─────────────────────────────────────
local function declareSettings()
    Core.RegisterModule('v-licenses', {
        label = 'Licences & permits', category = 'law',
        settings = {
            { key = 'pointLimit',  label = 'Points before suspension', type = 'number', default = Config.Points.limit, min = 1, max = 50, step = 1 },
            { key = 'suspendDays', label = 'Suspension length (days)', type = 'number', default = Config.Points.suspendDays, min = 1, max = 365, step = 1 },
        },
    })
end

local function applySettings()
    Config.Points.limit       = Core.GetSetting('v-licenses', 'pointLimit', Config.Points.limit)
    Config.Points.suspendDays = Core.GetSetting('v-licenses', 'suspendDays', Config.Points.suspendDays)
end

AddEventHandler('v-core:server:settingChanged', function(mod)
    if mod == 'v-licenses' then applySettings() end
end)
