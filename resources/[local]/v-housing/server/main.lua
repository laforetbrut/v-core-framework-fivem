-- v-housing | server
-- Property and tenancy. A motel is not a second system: it is a row with `tenancy = rent`,
-- a smaller stash and no garage.
--
-- Everything that lives inside a property is already built elsewhere and is reused rather
-- than reimplemented: storage is a `v-inventory` stash keyed by property id, the wardrobe
-- is `v-clothing`, and keys follow the `v-vehicles` model - giveable, revocable, checked
-- server-side. A key list on the client is not a lock.

local Core
local Props = {}          -- [id] = world row
local Inside = {}         -- [source] = { id, door = vector3 }

local function num(v, d) return tonumber(v) or d or 0 end

local function L(src, k)
    local p = Core and Core.GetPlayer(src)
    local lang = (p and p.lang) or 'fr'
    return (Locales[lang] or Locales.fr or {})[k] or k
end

-- ── Settings ──────────────────────────────────────────────────
V.Module({
    label = 'Housing', category = 'world',
    settings = {
        { key = 'enabled',    label = 'Property enabled',        type = 'bool',   default = true },
        { key = 'distance',   label = 'Door reach (m)',          type = 'number', default = Config.Distance, min = 1, max = 10, step = 0.5 },
        { key = 'blips',      label = 'Show property blips',     type = 'bool',   default = true,
          hint = 'Off hides every door, including the ones for sale.' },
        { key = 'maxOwned',   label = 'Properties one character may hold', type = 'number', default = 2, min = 1, max = 20, step = 1 },
        { key = 'priceMult',  label = 'Purchase price multiplier', type = 'number', default = 1.0, min = 0, max = 10, step = 0.05 },
        { key = 'rentMult',   label = 'Rent multiplier',         type = 'number', default = 1.0, min = 0, max = 10, step = 0.05 },
        { key = 'rentHours',  label = 'Rent charged every (h)',  type = 'number', default = Config.Rent.intervalHours, min = 1, max = 720, step = 1 },
        { key = 'graceDays',  label = 'Days of arrears before the door locks', type = 'number', default = Config.Rent.graceDays, min = 0, max = 30, step = 1 },
        { key = 'sellRate',   label = 'Sell-back rate',          type = 'number', default = 0.6, min = 0, max = 1, step = 0.05 },
        { key = 'stash',      label = 'Storage enabled',         type = 'bool',   default = true },
        { key = 'wardrobe',   label = 'Wardrobe enabled',        type = 'bool',   default = true },
    },
})

-- ── World data ────────────────────────────────────────────────
local function pushProps(src)
    local out = {}
    for id, p in pairs(Props) do
        out[id] = { id = id, label = p.label, kind = p.kind, x = p.x, y = p.y, z = p.z, h = p.h,
                    price = math.floor(num(p.price) * num(V.Setting('priceMult', 1.0), 1.0)),
                    rent = math.floor(num(p.rent) * num(V.Setting('rentMult', 1.0), 1.0)),
                    tenancy = p.tenancy, garage = p.garage, blip = p.blip }
    end
    TriggerClientEvent('v-housing:client:props', src or -1, out, V.SettingBool('blips', true))
end

local function loadProps()
    Props = {}
    if GetResourceState('v-world') ~= 'started' then return end
    for _, p in ipairs(exports['v-world']:GetProperties() or {}) do
        if p.enabled ~= false then Props[p.id] = p end
    end
    pushProps()
end

AddEventHandler('v-world:server:changed', function(domain)
    if domain == nil or domain == 'properties' then loadProps() end
end)

RegisterNetEvent('v-housing:server:request', function() pushProps(source) end)

-- ── Tenancy ───────────────────────────────────────────────────
local function tenancyOf(cid, id)
    return MySQL.single.await(
        'SELECT *, DATEDIFF(NOW(), paid_until) AS arrears FROM property_owners WHERE property = ? AND citizenid = ?',
        { id, cid })
end

local function hasKey(cid, id)
    if tenancyOf(cid, id) then return true end
    return MySQL.scalar.await(
        'SELECT 1 FROM property_keys WHERE property = ? AND citizenid = ?', { id, cid }) ~= nil
end

--- Locked, not deleted. A tenant in arrears past the grace period cannot open the door;
--- paying clears it and everything inside is exactly where they left it.
local function isLocked(row)
    if not row then return false end
    if row.locked == 1 then return true end
    local grace = math.floor(num(V.Setting('graceDays', Config.Rent.graceDays), Config.Rent.graceDays))
    return math.floor(num(row.arrears)) > grace
end

-- ── Callbacks ─────────────────────────────────────────────────
V.Callback('v-housing:info', function(src, resolve, data)
    local p = Core.GetPlayer(src)
    local prop = Props[tostring((data and data.id) or '')]
    if not p or not prop then resolve({ error = 'noprop' }) return end

    local row = tenancyOf(p.citizenid, prop.id)
    local ownerCid = MySQL.scalar.await('SELECT citizenid FROM property_owners WHERE property = ? LIMIT 1', { prop.id })

    resolve({
        ok = true,
        id = prop.id, label = prop.label, kind = prop.kind,
        price = math.floor(num(prop.price) * num(V.Setting('priceMult', 1.0), 1.0)),
        rent  = math.floor(num(prop.rent)  * num(V.Setting('rentMult', 1.0), 1.0)),
        tenancy = prop.tenancy,
        mine = row ~= nil, keyed = hasKey(p.citizenid, prop.id),
        taken = ownerCid ~= nil, locked = isLocked(row),
        arrears = row and math.max(0, math.floor(num(row.arrears))) or 0,
        garage = prop.garage == true,
        stash = V.SettingBool('stash', true), wardrobe = V.SettingBool('wardrobe', true),
    })
end)

V.Callback('v-housing:acquire', function(src, resolve, data)
    if not V.SettingBool('enabled', true) then resolve({ error = 'off' }) return end
    local p = Core.GetPlayer(src)
    local prop = Props[tostring((data and data.id) or '')]
    if not p or not prop then resolve({ error = 'noprop' }) return end

    -- Proximity re-derived: a client that names its own door can buy a house from a bus.
    local ped = GetPlayerPed(src)
    if #(GetEntityCoords(ped) - vector3(prop.x + 0.0, prop.y + 0.0, prop.z + 0.0))
       > (num(V.Setting('distance', Config.Distance), Config.Distance) + 4.0) then
        resolve({ error = 'far' }) return
    end

    local taken = MySQL.scalar.await('SELECT 1 FROM property_owners WHERE property = ? LIMIT 1', { prop.id })
    if taken then resolve({ error = 'taken' }) return end

    local mine = MySQL.scalar.await('SELECT COUNT(*) FROM property_owners WHERE citizenid = ?', { p.citizenid }) or 0
    local maxOwned = math.floor(num(V.Setting('maxOwned', 2), 2))
    if mine >= maxOwned then resolve({ error = 'toomany' }) return end

    -- Renting charges the first period up front; buying charges the price. Both go through
    -- the player's bank, so the anticheat and the audit log see an ordinary transaction.
    local rent = math.floor(num(prop.rent) * num(V.Setting('rentMult', 1.0), 1.0))
    local price = math.floor(num(prop.price) * num(V.Setting('priceMult', 1.0), 1.0))
    local due = (prop.tenancy == 'rent') and rent or price
    if due > 0 and not p.RemoveMoney('bank', due, 'property') then resolve({ error = 'funds' }) return end

    local hours = math.floor(num(V.Setting('rentHours', Config.Rent.intervalHours), Config.Rent.intervalHours))
    MySQL.insert.await([[INSERT INTO property_owners (property, citizenid, tenancy, paid_until, locked)
        VALUES (?,?,?, DATE_ADD(NOW(), INTERVAL ? HOUR), 0)]],
        { prop.id, p.citizenid, prop.tenancy, (prop.tenancy == 'rent') and hours or 87600 })

    Core.Log('housing', ('%s %s %s for %d'):format(p.citizenid,
        prop.tenancy == 'rent' and 'rented' or 'bought', prop.id, due), nil, p.citizenid)
    resolve({ ok = true, paid = due })
end)

V.Callback('v-housing:release', function(src, resolve, data)
    local p = Core.GetPlayer(src)
    local prop = Props[tostring((data and data.id) or '')]
    if not p or not prop then resolve({ error = 'noprop' }) return end
    local row = tenancyOf(p.citizenid, prop.id)
    if not row then resolve({ error = 'notyours' }) return end

    -- Selling back pays a rate of the purchase price; a rental refunds nothing, which is
    -- what renting means.
    local back = 0
    if prop.tenancy ~= 'rent' then
        back = math.floor(num(prop.price) * num(V.Setting('priceMult', 1.0), 1.0)
                          * num(V.Setting('sellRate', 0.6), 0.6))
        if back > 0 then p.AddMoney('bank', back, 'property-sale') end
    end

    MySQL.query.await('DELETE FROM property_owners WHERE property = ? AND citizenid = ?', { prop.id, p.citizenid })
    MySQL.query.await('DELETE FROM property_keys WHERE property = ?', { prop.id })
    Core.Log('housing', ('%s released %s (back %d)'):format(p.citizenid, prop.id, back), nil, p.citizenid)
    resolve({ ok = true, refund = back })
end)

V.Callback('v-housing:payRent', function(src, resolve, data)
    local p = Core.GetPlayer(src)
    local prop = Props[tostring((data and data.id) or '')]
    if not p or not prop then resolve({ error = 'noprop' }) return end
    local row = tenancyOf(p.citizenid, prop.id)
    if not row then resolve({ error = 'notyours' }) return end

    local rent = math.floor(num(prop.rent) * num(V.Setting('rentMult', 1.0), 1.0))
    local owed = math.max(1, math.floor(num(row.arrears)) + 1) * rent
    if owed > 0 and not p.RemoveMoney('bank', owed, 'rent') then resolve({ error = 'funds', owed = owed }) return end

    local hours = math.floor(num(V.Setting('rentHours', Config.Rent.intervalHours), Config.Rent.intervalHours))
    MySQL.update.await(
        'UPDATE property_owners SET paid_until = DATE_ADD(NOW(), INTERVAL ? HOUR), locked = 0 WHERE property = ? AND citizenid = ?',
        { hours, prop.id, p.citizenid })
    resolve({ ok = true, paid = owed })
end)

--- Enter. The bucket is what makes a shared shell work: everyone in the same property sees
--- each other and nobody else, and one interior serves every property that uses it.
V.Callback('v-housing:enter', function(src, resolve, data)
    local p = Core.GetPlayer(src)
    local prop = Props[tostring((data and data.id) or '')]
    if not p or not prop then resolve({ error = 'noprop' }) return end
    if not hasKey(p.citizenid, prop.id) then resolve({ error = 'nokey' }) return end

    local row = tenancyOf(p.citizenid, prop.id)
    if isLocked(row) then resolve({ error = 'locked' }) return end

    local shell = Config.Shells[prop.shell] or Config.Shells.apartment
    -- Without a bucket, two players in "the same" apartment stand in the same room.
    local bucket = Config.BucketBase + (tonumber(string.byte(prop.id, 1) or 65) * 997
                   + #prop.id * 31 + (tonumber(prop.id:match('(%d+)') or 0) or 0))
    SetPlayerRoutingBucket(src, bucket)
    SetRoutingBucketPopulationEnabled(bucket, false)

    local ped = GetPlayerPed(src)
    Inside[src] = { id = prop.id, door = GetEntityCoords(ped) }
    V.Use('v-anticheat').Expect(src, 'teleport', 15)

    resolve({ ok = true, shell = shell, id = prop.id,
              stash = V.SettingBool('stash', true) and ('property:' .. prop.id) or nil,
              slots = math.floor(num(prop.slots, 40)),
              wardrobe = V.SettingBool('wardrobe', true) })
end)

V.Callback('v-housing:exit', function(src, resolve)
    local st = Inside[src]
    if not st then resolve({ error = 'notinside' }) return end
    SetPlayerRoutingBucket(src, 0)
    V.Use('v-anticheat').Expect(src, 'teleport', 15)
    Inside[src] = nil
    resolve({ ok = true, door = { x = st.door.x, y = st.door.y, z = st.door.z } })
end)

--- Keys, the v-vehicles way: giveable and revocable, and the list lives here.
V.Callback('v-housing:giveKey', function(src, resolve, data)
    local p = Core.GetPlayer(src)
    local prop = Props[tostring((data and data.id) or '')]
    if not p or not prop then resolve({ error = 'noprop' }) return end
    if not tenancyOf(p.citizenid, prop.id) then resolve({ error = 'notyours' }) return end

    local target = tonumber(data and data.target)
    if not target then resolve({ error = 'notarget' }) return end
    local tp = Core.GetPlayer(target)
    if not tp then resolve({ error = 'notarget' }) return end

    -- Standing there, not a citizen id typed from a message.
    local a, b = GetPlayerPed(src), GetPlayerPed(target)
    if #(GetEntityCoords(a) - GetEntityCoords(b)) > 4.0 then resolve({ error = 'far' }) return end

    MySQL.insert.await('INSERT IGNORE INTO property_keys (property, citizenid) VALUES (?,?)',
        { prop.id, tp.citizenid })
    Core.Notify(target, L(target, 'house.got_key'), 'success')
    resolve({ ok = true })
end)

--- Storage. Routed through here rather than letting the client name a stash id: the key
--- check is the whole point, and v-inventory has no idea what a property is.
V.Callback('v-housing:stash', function(src, resolve)
    if not V.SettingBool('stash', true) then resolve({ error = 'off' }) return end
    local p = Core.GetPlayer(src)
    local st = Inside[src]
    if not p or not st then resolve({ error = 'notinside' }) return end
    if not hasKey(p.citizenid, st.id) then resolve({ error = 'nokey' }) return end
    V.Use('v-inventory').OpenSharedStash(src, 'property:' .. st.id)
    resolve({ ok = true })
end)

V.Callback('v-housing:mine', function(src, resolve)
    local p = Core.GetPlayer(src)
    if not p then resolve(false) return end
    local rows = MySQL.query.await([[SELECT o.property, o.tenancy, o.locked,
        DATEDIFF(NOW(), o.paid_until) AS arrears FROM property_owners o WHERE o.citizenid = ?]],
        { p.citizenid }) or {}
    for _, r in ipairs(rows) do
        local prop = Props[r.property]
        r.label = prop and prop.label or r.property
        r.kind = prop and prop.kind or 'house'
        r.locked = isLocked(r)
    end
    resolve({ ok = true, rows = rows })
end)

-- ── Rent clock ────────────────────────────────────────────────
-- Arrears are derived from `paid_until` rather than ticked, so a restart loses nothing and
-- a tenant who was offline for a week owes exactly a week.
CreateThread(function()
    while GetResourceState('oxmysql') ~= 'started' do Wait(100) end

    MySQL.query.await([[CREATE TABLE IF NOT EXISTS `property_owners` (
        `property` VARCHAR(40) NOT NULL,
        `citizenid` VARCHAR(32) NOT NULL,
        `tenancy` VARCHAR(8) NOT NULL DEFAULT 'own',
        `since` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        `paid_until` DATETIME NOT NULL,
        `locked` TINYINT(1) NOT NULL DEFAULT 0,
        PRIMARY KEY (`property`), KEY `cid_idx` (`citizenid`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])

    MySQL.query.await([[CREATE TABLE IF NOT EXISTS `property_keys` (
        `property` VARCHAR(40) NOT NULL,
        `citizenid` VARCHAR(32) NOT NULL,
        PRIMARY KEY (`property`, `citizenid`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])

    while true do
        Wait(600000)   -- ten minutes; rent is a daily thing, not a per-tick one
        local grace = math.floor(num(V.Setting('graceDays', Config.Rent.graceDays), Config.Rent.graceDays))
        -- Locking is a flag, never a delete. A locked property can be paid off; a deleted
        -- one has taken the tenant's stash with it.
        pcall(function()
            MySQL.update.await(
                "UPDATE property_owners SET locked = 1 WHERE tenancy = 'rent' AND locked = 0 AND DATEDIFF(NOW(), paid_until) > ?",
                { grace })
        end)
    end
end)

AddEventHandler('playerDropped', function() Inside[source] = nil end)

V.Ready(function(core)
    Core = core
    local tries = 0
    while GetResourceState('v-world') == 'started' and not exports['v-world']:IsReady() and tries < 150 do
        Wait(100); tries = tries + 1
    end
    if GetResourceState('v-world') == 'started' then
        exports['v-world']:SeedProperties(Config.Properties)
        loadProps()
    end
end)

-- ── Exports ───────────────────────────────────────────────────
exports('GetProperties', function() return Props end)
exports('HasKey',    function(cid, id) return hasKey(tostring(cid or ''), tostring(id or '')) end)
exports('OwnerOf',   function(id)
    return MySQL.scalar.await('SELECT citizenid FROM property_owners WHERE property = ? LIMIT 1', { tostring(id or '') })
end)
exports('IsInside',  function(src) return Inside[src] and Inside[src].id or nil end)
exports('StashId',   function(id) return 'property:' .. tostring(id or '') end)
