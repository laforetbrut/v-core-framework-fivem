-- v-police | server
-- Street work (cuff, escort, search, seize), the booking side (charges, fines, jail) and
-- the MDT (records, warrants).
--
-- Two rules run through the whole file. **Police is a job, not a permission** — staff are
-- not police, and an admin who wants to arrest somebody should be given the job. And
-- **every target is re-derived server-side**: the client sends a player id and nothing
-- else, and proximity, ownership and rank are all measured here.

local Core
local Charges = {}
local Cuffed  = {}    -- [source] = true
local Escort  = {}    -- [detainee] = officerSource

local function num(v, d) return tonumber(v) or d or 0 end

local function L(src, k)
    local p = Core and Core.GetPlayer(src)
    local lang = (p and p.lang) or 'fr'
    return (Locales[lang] or Locales.fr or {})[k] or k
end

-- ── Settings ──────────────────────────────────────────────────
V.Module({
    label = 'Police', category = 'people',
    settings = {
        { key = 'distance',    label = 'Interaction range (m)',   type = 'number', default = Config.Distance, min = 1, max = 10, step = 0.5 },
        { key = 'requireDuty', label = 'Officers must be on duty', type = 'bool',  default = true },
        { key = 'cuffItem',    label = 'Handcuff item required (blank = none)', type = 'string', default = Config.CuffItem, maxLength = 40 },
        { key = 'maxJail',     label = 'Maximum jail sentence (minutes)', type = 'number', default = Config.Jail.maxMinutes, min = 1, max = 1440, step = 5 },
        { key = 'fineAccount', label = 'Fines are taken from',    type = 'select', default = 'bank',
          options = { { value = 'bank', label = 'Bank' }, { value = 'cash', label = 'Cash' } } },
        { key = 'fineToTreasury', label = 'Fines go to the department treasury', type = 'bool', default = false },
        { key = 'allowSeize',  label = 'Officers can seize items', type = 'bool',  default = true },
        { key = 'jailBlip',    label = 'Show the prison blip',    type = 'bool',   default = true },
        { key = 'warrantAuto', label = 'Charging someone clears their warrants', type = 'bool', default = true },
    },
})

-- Consumers ask for the capability, not the resource: a server that replaces this
-- module keeps every consumer working.
V.Provide('police')


-- ── Who is police? ────────────────────────────────────────────
local function isCop(src)
    local p = Core.GetPlayer(src)
    if not p or type(p.job) ~= 'table' then return false end
    if not Config.Jobs[p.job.name] then return false end
    if V.SettingBool('requireDuty', true) then
        return V.Use('v-jobs').IsOnDuty(src) == true
    end
    return true
end

local function copJob(src)
    local p = Core.GetPlayer(src)
    return (p and type(p.job) == 'table') and p.job.name or nil
end

--- The target, re-derived: the client sends a player id, we measure the distance.
local function targetNear(src, targetId)
    targetId = tonumber(targetId)
    if not targetId or targetId == src then return nil end
    local a, b = GetPlayerPed(src), GetPlayerPed(targetId)
    if not a or a == 0 or not b or b == 0 then return nil end
    local range = num(V.Setting('distance', Config.Distance), Config.Distance) + 1.5
    if #(GetEntityCoords(a) - GetEntityCoords(b)) > range then return nil end
    return targetId
end

-- ── Cuffs ─────────────────────────────────────────────────────
local function setCuffed(target, on)
    Cuffed[target] = on or nil
    TriggerClientEvent('v-police:client:cuffed', target, on and true or false)
end

V.Callback('v-police:cuff', function(src, resolve, data)
    if not isCop(src) then resolve({ error = 'notcop' }) return end
    local target = targetNear(src, data and data.target)
    if not target then resolve({ error = 'far' }) return end

    local item = tostring(V.Setting('cuffItem', Config.CuffItem) or '')
    if item ~= '' and not Cuffed[target] then
        -- v-inventory counts rather than answering yes/no; asking it the way it wants
        -- to be asked beats adding a HasItem it does not have.
        local count = V.Use('v-inventory').GetItemCount(src, item)
        if (tonumber(count) or 0) < 1 then resolve({ error = 'noitem' }) return end
    end

    local on = not Cuffed[target]
    setCuffed(target, on)
    if not on then Escort[target] = nil; TriggerClientEvent('v-police:client:escort', target, nil) end

    V.Use('v-3dsound').PlayFromPlayer(target, 'cuff')
    Core.Notify(target, L(target, on and 'pol.you_cuffed' or 'pol.you_uncuffed'), on and 'error' or 'success')
    Core.Log('police', ('%s %s player %d'):format(copJob(src) or '?', on and 'cuffed' or 'uncuffed', target),
        { by = src })
    resolve({ ok = true, cuffed = on })
end)

-- ── Escort ────────────────────────────────────────────────────
V.Callback('v-police:escort', function(src, resolve, data)
    if not isCop(src) then resolve({ error = 'notcop' }) return end
    local target = targetNear(src, data and data.target)
    if not target then resolve({ error = 'far' }) return end
    -- Only a cuffed detainee can be dragged: otherwise "escort" is a way to move any
    -- player anywhere against their will.
    if not Cuffed[target] then resolve({ error = 'notcuffed' }) return end

    if Escort[target] == src then
        Escort[target] = nil
        TriggerClientEvent('v-police:client:escort', target, nil)
        resolve({ ok = true, escorting = false })
    else
        Escort[target] = src
        TriggerClientEvent('v-police:client:escort', target, src)
        resolve({ ok = true, escorting = true })
    end
end)

-- ── Search ────────────────────────────────────────────────────
V.Callback('v-police:search', function(src, resolve, data)
    if not isCop(src) then resolve({ error = 'notcop' }) return end
    local target = targetNear(src, data and data.target)
    if not target then resolve({ error = 'far' }) return end

    -- GetSearchable is v-inventory's own idea of what a search may see: it already never
    -- exposes the hidden pocket, and re-deriving that here would fork the rule.
    local items = V.Use('v-inventory').GetSearchable(target) or {}
    local tp = Core.GetPlayer(target)
    Core.Notify(target, L(target, 'pol.you_searched'), 'warning')
    resolve({
        ok = true,
        target = target,
        name = tp and ('%s %s'):format(tp.firstname or '', tp.lastname or '') or '',
        citizenid = tp and tp.citizenid or nil,
        items = items,
    })
end)

V.Callback('v-police:seize', function(src, resolve, data)
    if not isCop(src) then resolve({ error = 'notcop' }) return end
    if not V.SettingBool('allowSeize', true) then resolve({ error = 'off' }) return end
    local target = targetNear(src, data and data.target)
    if not target then resolve({ error = 'far' }) return end

    local item = tostring((data and data.item) or '')
    local qty = math.max(1, math.floor(num(data and data.count, 1)))
    if item == '' then resolve({ error = 'item' }) return end

    -- Seized goods leave the world rather than moving to the officer: evidence that lands
    -- in a policeman's pocket is indistinguishable from theft.
    local ok = V.Use('v-inventory').RemoveItem(target, item, qty)
    if ok ~= true then resolve({ error = 'item' }) return end

    Core.Notify(target, (L(target, 'pol.seized')):format(qty, item), 'error')
    Core.Log('police', ('seized %dx %s from player %d'):format(qty, item, target), { by = src })
    resolve({ ok = true })
end)

-- ── Charges, fines and jail ───────────────────────────────────
local function chargeByCode(code)
    for _, c in ipairs(Charges) do
        if c.code == code and c.enabled ~= false then return c end
    end
    return nil
end

V.Callback('v-police:charges', function(src, resolve)
    if not isCop(src) then resolve({ error = 'notcop' }) return end
    resolve({ ok = true, charges = Charges })
end)

V.Callback('v-police:book', function(src, resolve, data)
    if not isCop(src) then resolve({ error = 'notcop' }) return end
    if type(data) ~= 'table' then resolve(false) return end
    local target = targetNear(src, data.target)
    if not target then resolve({ error = 'far' }) return end

    local tp, op = Core.GetPlayer(target), Core.GetPlayer(src)
    if not tp or not op then resolve(false) return end

    -- The sentence is re-derived from the penal code: the client sends codes, never
    -- amounts. A client that could name its own fine could also name a negative one.
    local codes, fine, jail, applied = {}, 0, 0, {}
    for _, code in ipairs(data.codes or {}) do
        local c = chargeByCode(tostring(code))
        if c then
            codes[#codes + 1] = c.code
            fine = fine + math.max(0, math.floor(num(c.fine)))
            jail = jail + math.max(0, math.floor(num(c.jail)))
            applied[#applied + 1] = c
        end
    end
    if #codes == 0 then resolve({ error = 'nocharge' }) return end

    local maxJail = math.floor(num(V.Setting('maxJail', Config.Jail.maxMinutes), Config.Jail.maxMinutes))
    jail = math.min(jail, maxJail)

    -- A fine that cannot be paid is a debt, not a failed arrest: the sentence stands.
    local account = tostring(V.Setting('fineAccount', 'bank'))
    local paid = fine > 0 and tp.RemoveMoney(account, fine, 'police-fine') or (fine == 0)
    if paid and fine > 0 and V.SettingBool('fineToTreasury', false) then
        V.Use('v-factions').Deposit(copJob(src) or 'police', 'job', fine, 'fine', op.citizenid)
    end

    -- Licence points are the licences module's business; a driving offence reaches it
    -- through the charge row rather than through a hardcoded list here.
    for _, c in ipairs(applied) do
        if num(c.points) > 0 and c.license then
            V.Use('v-licenses').AddPoints(tp.citizenid, c.license, math.floor(num(c.points)))
        end
    end

    MySQL.insert.await([[INSERT INTO police_records
        (citizenid, charges, fine, jail, paid, officer_cid, notes) VALUES (?,?,?,?,?,?,?)]],
        { tp.citizenid, json.encode(codes), fine, jail, paid and 1 or 0, op.citizenid,
          tostring(data.notes or ''):sub(1, 240) })

    if V.SettingBool('warrantAuto', true) then
        MySQL.update.await('UPDATE police_warrants SET active = 0 WHERE citizenid = ? AND active = 1',
            { tp.citizenid })
    end

    if jail > 0 then
        MySQL.query.await([[INSERT INTO police_jail (citizenid, release_at) VALUES (?, DATE_ADD(NOW(), INTERVAL ? MINUTE))
            ON DUPLICATE KEY UPDATE release_at = DATE_ADD(NOW(), INTERVAL ? MINUTE)]],
            { tp.citizenid, jail, jail })
        -- Tell the anticheat this jump is ours, or the framework flags itself.
        V.Use('v-anticheat').Expect(target, 'teleport', 15)
        TriggerClientEvent('v-police:client:jail', target, jail, Config.Jail)
    end

    Core.Notify(target, (L(target, 'pol.booked')):format(fine, jail), 'error')
    if not paid then Core.Notify(target, L(target, 'pol.fine_unpaid'), 'warning') end
    Core.Log('police', ('booked %s: %s (fine %d, jail %d)'):format(
        tp.citizenid, table.concat(codes, ', '), fine, jail), { by = src }, op.citizenid)

    resolve({ ok = true, fine = fine, jail = jail, paid = paid })
end)

-- ── Jail persistence ──────────────────────────────────────────
--- Minutes left, or 0. Read on spawn so a relog is not an escape.
local function jailLeft(cid)
    local left = MySQL.scalar.await(
        'SELECT GREATEST(0, TIMESTAMPDIFF(MINUTE, NOW(), release_at)) FROM police_jail WHERE citizenid = ?',
        { cid })
    return math.max(0, math.floor(num(left)))
end

AddEventHandler('v-core:server:onPlayerLoaded', function(src)
    local p = Core.GetPlayer(src)
    if not p then return end
    local left = jailLeft(p.citizenid)
    if left > 0 then
        V.Use('v-anticheat').Expect(src, 'teleport', 15)
        TriggerClientEvent('v-police:client:jail', src, left, Config.Jail)
    else
        MySQL.query.await('DELETE FROM police_jail WHERE citizenid = ?', { p.citizenid })
    end
end)

V.Callback('v-police:jailLeft', function(src, resolve)
    local p = Core.GetPlayer(src)
    resolve(p and jailLeft(p.citizenid) or 0)
end)

RegisterNetEvent('v-police:server:released', function()
    local src = source
    local p = Core.GetPlayer(src)
    if not p then return end
    -- Re-derived: a client saying "I am free" is only believed when the row agrees.
    if jailLeft(p.citizenid) > 0 then return end
    MySQL.query.await('DELETE FROM police_jail WHERE citizenid = ?', { p.citizenid })
end)

-- ── MDT ───────────────────────────────────────────────────────
V.Callback('v-police:lookup', function(src, resolve, data)
    if not isCop(src) then resolve({ error = 'notcop' }) return end
    local q = tostring((data and data.query) or ''):sub(1, 40)
    if q == '' then resolve({ error = 'query' }) return end

    local row = MySQL.single.await([[SELECT citizenid, firstname, lastname, dob FROM characters
        WHERE citizenid = ? OR CONCAT(firstname, ' ', lastname) LIKE ? LIMIT 1]],
        { q:upper(), '%' .. q .. '%' })
    if not row then resolve({ error = 'nobody' }) return end

    local records = MySQL.query.await([[SELECT charges, fine, jail, paid, officer_cid, notes, at
        FROM police_records WHERE citizenid = ? ORDER BY id DESC LIMIT 25]], { row.citizenid }) or {}
    for _, r in ipairs(records) do
        if type(r.charges) == 'string' then r.charges = json.decode(r.charges) or {} end
    end

    resolve({
        ok = true,
        person = row,
        records = records,
        warrants = MySQL.query.await(
            'SELECT id, reason, by_cid, at FROM police_warrants WHERE citizenid = ? AND active = 1 ORDER BY id DESC',
            { row.citizenid }) or {},
        licenses = V.Use('v-licenses').GetAllByCid(row.citizenid) or {},
        vehicles = MySQL.query.await(
            'SELECT plate, model, state FROM character_vehicles WHERE citizenid = ? ORDER BY plate',
            { row.citizenid }) or {},
        jail = jailLeft(row.citizenid),
    })
end)

V.Callback('v-police:warrant', function(src, resolve, data)
    if not isCop(src) then resolve({ error = 'notcop' }) return end
    if type(data) ~= 'table' then resolve(false) return end
    local op = Core.GetPlayer(src)
    local cid = tostring(data.citizenid or ''):upper()
    if cid == '' then resolve({ error = 'nobody' }) return end

    if data.clear then
        MySQL.update.await('UPDATE police_warrants SET active = 0 WHERE citizenid = ? AND active = 1', { cid })
    else
        local reason = tostring(data.reason or ''):sub(1, 200)
        if reason == '' then resolve({ error = 'reason' }) return end
        MySQL.insert.await('INSERT INTO police_warrants (citizenid, reason, by_cid) VALUES (?,?,?)',
            { cid, reason, op and op.citizenid or nil })
    end
    Core.Log('police', ('warrant %s for %s'):format(data.clear and 'cleared' or 'issued', cid),
        { by = src }, op and op.citizenid or nil)
    resolve({ ok = true })
end)

V.Callback('v-police:warrants', function(src, resolve)
    if not isCop(src) then resolve({ error = 'notcop' }) return end
    resolve({ ok = true, rows = MySQL.query.await([[SELECT w.id, w.citizenid, w.reason, w.at,
        c.firstname, c.lastname FROM police_warrants w
        LEFT JOIN characters c ON c.citizenid = w.citizenid
        WHERE w.active = 1 ORDER BY w.id DESC LIMIT 100]]) or {} })
end)

-- ── Impound ───────────────────────────────────────────────────
V.Callback('v-police:impound', function(src, resolve, data)
    if not isCop(src) then resolve({ error = 'notcop' }) return end
    local netid = tonumber(data and data.netid)
    local ent = netid and NetworkGetEntityFromNetworkId(netid) or 0
    if not ent or ent == 0 or not DoesEntityExist(ent) then resolve({ error = 'novehicle' }) return end

    local ped = GetPlayerPed(src)
    if #(GetEntityCoords(ent) - GetEntityCoords(ped)) > 12.0 then resolve({ error = 'far' }) return end

    local plate = GetVehicleNumberPlateText(ent):gsub('%s+$', '')
    local row = V.Use('v-vehicles').GetVehicle(plate)
    if not row then
        -- Not an owned car: it is scenery or a rental, so it just goes away.
        DeleteEntity(ent)
        resolve({ ok = true, owned = false }) return
    end

    -- v-garages owns the impound state; setting it here rather than deleting the row is
    -- what lets the owner buy it back at the lot.
    V.Use('v-vehicles').DespawnOwned(plate, nil, 2)
    Core.Log('police', ('impounded %s'):format(plate), { by = src })
    resolve({ ok = true, owned = true, plate = plate })
end)

-- ── Boot ──────────────────────────────────────────────────────
CreateThread(function()
    while GetResourceState('oxmysql') ~= 'started' do Wait(100) end

    MySQL.query.await([[CREATE TABLE IF NOT EXISTS `police_records` (
        `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
        `citizenid` VARCHAR(32) NOT NULL,
        `charges` JSON NOT NULL,
        `fine` INT NOT NULL DEFAULT 0,
        `jail` INT NOT NULL DEFAULT 0,
        `paid` TINYINT(1) NOT NULL DEFAULT 1,
        `officer_cid` VARCHAR(32) DEFAULT NULL,
        `notes` VARCHAR(240) NOT NULL DEFAULT '',
        `at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (`id`), KEY `cid_idx` (`citizenid`, `id`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])

    MySQL.query.await([[CREATE TABLE IF NOT EXISTS `police_warrants` (
        `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
        `citizenid` VARCHAR(32) NOT NULL,
        `reason` VARCHAR(200) NOT NULL,
        `by_cid` VARCHAR(32) DEFAULT NULL,
        `active` TINYINT(1) NOT NULL DEFAULT 1,
        `at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (`id`), KEY `cid_idx` (`citizenid`, `active`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])

    -- Jail is a row, not a timer: a timer dies with a restart and a relog would be an
    -- escape. The release time is absolute.
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS `police_jail` (
        `citizenid` VARCHAR(32) NOT NULL,
        `release_at` DATETIME NOT NULL,
        PRIMARY KEY (`citizenid`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
end)

local function loadCharges()
    if GetResourceState('v-world') ~= 'started' then return end
    Charges = exports['v-world']:GetCharges() or {}
end

AddEventHandler('v-world:server:changed', function(domain)
    if domain == nil or domain == 'charges' then loadCharges() end
end)

V.Ready(function(core)
    Core = core
    local tries = 0
    while GetResourceState('v-world') == 'started' and not exports['v-world']:IsReady() and tries < 100 do
        Wait(100); tries = tries + 1
    end
    if GetResourceState('v-world') == 'started' then
        exports['v-world']:SeedCharges(Config.Charges)
        loadCharges()
    end
end)

-- ── Exports ───────────────────────────────────────────────────
exports('IsCop',    function(src) return isCop(src) end)
exports('IsCuffed', function(src) return Cuffed[src] == true end)
exports('JailLeft', function(cid) return jailLeft(cid) end)
exports('GetCharges', function() return Charges end)
exports('HasWarrant', function(cid)
    return MySQL.scalar.await(
        'SELECT 1 FROM police_warrants WHERE citizenid = ? AND active = 1 LIMIT 1', { cid }) ~= nil
end)

AddEventHandler('playerDropped', function()
    Cuffed[source] = nil
    Escort[source] = nil
    for detainee, officer in pairs(Escort) do
        if officer == source then Escort[detainee] = nil end
    end
end)
