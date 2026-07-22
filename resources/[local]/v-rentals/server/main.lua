-- v-rentals | server
-- Short-term hire. The rule that keeps this from becoming a free-car exploit: a rental
-- NEVER creates a `character_vehicles` row. It lives in `vehicle_rentals`, it carries a
-- temporary plate, and the deposit is only ever returned by bringing the car back.
--
-- v-vehicles owns owned cars and their keys; we borrow its key system (which is not
-- ownership-gated) and spawn our own entity, because SpawnOwned needs a row we must not
-- create.

local Core
local Points = {}
local Live = {}          -- [plate] = { entity, netid, src }

local function L(src, k)
    local lang = 'fr'
    if src then
        local p = Core and Core.GetPlayer(src)
        lang = (p and p.lang) or 'fr'
    end
    return (Locales[lang] or Locales.fr or {})[k] or k
end

local function num(v, d) return tonumber(v) or d or 0 end

-- ── Settings ──────────────────────────────────────────────────
V.Module({
    label = 'Rentals', category = 'vehicles',
    settings = {
        { key = 'distance',   label = 'Interaction range (m)',   type = 'number', default = Config.Distance, min = 1, max = 15, step = 0.5 },
        { key = 'duration',   label = 'Hire length (minutes)',   type = 'number', default = Config.Duration, min = 5, max = 1440, step = 5 },
        { key = 'warnAt',     label = 'Warn when N minutes left', type = 'number', default = Config.WarnAt, min = 0, max = 60, step = 1 },
        { key = 'refundOnTime', label = 'Refund the deposit on a return in time', type = 'bool', default = Config.RefundOnTime },
        { key = 'requireLicense', label = 'Require a driving licence', type = 'bool', default = true },
        { key = 'depositMult', label = 'Deposit multiplier',      type = 'number', default = 1.0, min = 0, max = 10, step = 0.05 },
        { key = 'feeMult',    label = 'Fee multiplier',           type = 'number', default = 1.0, min = 0, max = 10, step = 0.05 },
        { key = 'blips',      label = 'Show rental blips',        type = 'bool',   default = true },
    },
})

-- ── World data ────────────────────────────────────────────────
local function pointById(id)
    for _, p in ipairs(Points) do
        if p.id == id and p.enabled ~= false then return p end
    end
    return nil
end

local function pushPoints(src)
    if src then TriggerClientEvent('v-rentals:client:points', src, Points)
    else TriggerClientEvent('v-rentals:client:points', -1, Points) end
end

local function loadPoints()
    if GetResourceState('v-world') ~= 'started' then return end
    Points = exports['v-world']:GetRentals() or {}
    pushPoints()
end

AddEventHandler('v-world:server:changed', function(domain)
    if domain == nil or domain == 'rentals' or domain == 'vehcat' then loadPoints() end
end)

RegisterNetEvent('v-rentals:server:request', function() pushPoints(source) end)

-- ── Catalogue ─────────────────────────────────────────────────
-- Rentability lives on the vehicle catalogue: a NULL deposit means "not for hire".
local function catalogueFor(point)
    local rows = MySQL.query.await(
        'SELECT model, label, cat, rent_deposit, rent_fee FROM vehicle_catalogue ' ..
        'WHERE enabled = 1 AND rent_deposit IS NOT NULL ORDER BY cat, rent_deposit') or {}

    local allow = {}
    for c in tostring(point.cats or ''):gmatch('[^,]+') do
        allow[c:gsub('%s', '')] = true
    end
    local dMult = num(V.Setting('depositMult', 1.0), 1.0)
    local fMult = num(V.Setting('feeMult', 1.0), 1.0)

    local out = {}
    for _, r in ipairs(rows) do
        -- An empty `cats` on the point means it hires out anything marked rentable.
        if not next(allow) or allow[r.cat] then
            out[#out + 1] = {
                model = r.model, label = r.label, cat = r.cat,
                deposit = math.max(0, math.floor(num(r.rent_deposit) * dMult)),
                fee     = math.max(0, math.floor(num(r.rent_fee) * fMult)),
            }
        end
    end
    return out
end

-- ── Plates ────────────────────────────────────────────────────
-- A rental plate is deliberately recognisable: the police should be able to tell a hire
-- car from an owned one at a glance, and it must never collide with a minted plate.
local function mintPlate()
    for _ = 1, 40 do
        local p = (Config.Plate or 'RENT') .. tostring(math.random(100, 999))
        local taken = Live[p]
            or MySQL.scalar.await('SELECT 1 FROM vehicle_rentals WHERE plate = ? AND state = ?', { p, 'active' })
            or MySQL.scalar.await('SELECT 1 FROM character_vehicles WHERE plate = ?', { p })
        if not taken then return p end
    end
    return nil
end

-- ── Proximity, re-derived server-side ─────────────────────────
local function nearPoint(src, point)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return false end
    local range = num(V.Setting('distance', Config.Distance), Config.Distance) + 4.0
    return #(GetEntityCoords(ped) - vector3(point.x + 0.0, point.y + 0.0, point.z + 0.0)) <= range
end

-- ── Open ──────────────────────────────────────────────────────
V.Callback('v-rentals:open', function(src, resolve, id)
    local point = pointById(tostring(id or ''))
    if not point then resolve({ error = 'point' }) return end
    if not nearPoint(src, point) then resolve({ error = 'far' }) return end

    local p = Core.GetPlayer(src)
    if not p then resolve(false) return end

    -- A player already holding a hire cannot take a second one out: that is how one
    -- deposit turns into a fleet.
    local active = MySQL.single.await(
        'SELECT plate, model, expires_at, deposit FROM vehicle_rentals WHERE citizenid = ? AND state = ?',
        { p.citizenid, 'active' })

    resolve({
        point   = { id = point.id, label = point.label },
        cars    = catalogueFor(point),
        active  = active,
        cash    = p.money.cash, bank = p.money.bank,
        minutes = math.floor(num(V.Setting('duration', Config.Duration), Config.Duration)),
    })
end)

-- ── Hire ──────────────────────────────────────────────────────
V.Callback('v-rentals:hire', function(src, resolve, data)
    if type(data) ~= 'table' then resolve(false) return end
    local point = pointById(tostring(data.point or ''))
    if not point then resolve({ error = 'point' }) return end
    if not nearPoint(src, point) then resolve({ error = 'far' }) return end

    local p = Core.GetPlayer(src)
    if not p then resolve(false) return end

    if V.SettingBool('requireLicense', true) then
        local lic = V.Use('v-licenses').Has(src, 'driver')
        if not lic then resolve({ error = 'license' }) return end
    end

    local held = MySQL.scalar.await(
        'SELECT 1 FROM vehicle_rentals WHERE citizenid = ? AND state = ?', { p.citizenid, 'active' })
    if held then resolve({ error = 'already' }) return end

    -- Re-derive the price from the catalogue: the client sent a model, nothing else.
    local model = tostring(data.model or ''):lower()
    local pick
    for _, c in ipairs(catalogueFor(point)) do
        if c.model == model then pick = c break end
    end
    if not pick then resolve({ error = 'model' }) return end

    local total = pick.deposit + pick.fee
    if not p.RemoveMoney('bank', total, 'rental-hire') then resolve({ error = 'funds' }) return end

    local plate = mintPlate()
    if not plate then p.AddMoney('bank', total, 'rental-refund'); resolve({ error = 'plate' }) return end

    local veh = CreateVehicle(joaat(model), point.sx + 0.0, point.sy + 0.0, point.sz + 0.0,
                              point.sh + 0.0, true, true)
    local tries = 0
    while not DoesEntityExist(veh) and tries < 100 do Wait(10); tries = tries + 1 end
    if not DoesEntityExist(veh) then
        -- the charge must never survive a failed spawn
        p.AddMoney('bank', total, 'rental-refund')
        resolve({ error = 'spawn' }) return
    end

    SetVehicleNumberPlateText(veh, plate)
    local netid = NetworkGetNetworkIdFromEntity(veh)
    Live[plate] = { entity = veh, netid = netid, src = src }
    V.Use('v-vehicles').GiveKeys(src, plate)

    local minutes = math.floor(num(V.Setting('duration', Config.Duration), Config.Duration))
    MySQL.insert.await([[INSERT INTO vehicle_rentals
        (plate, citizenid, model, point, deposit, fee, expires_at, state)
        VALUES (?,?,?,?,?,?, DATE_ADD(NOW(), INTERVAL ? MINUTE), 'active')]],
        { plate, p.citizenid, model, point.id, pick.deposit, pick.fee, minutes })

    Core.Log('vehicles', ('%s hired %s (%s) at %s for %d min'):format(
        p.citizenid, model, plate, point.id, minutes), nil, p.citizenid)

    resolve({ ok = true, netid = netid, plate = plate, minutes = minutes,
              deposit = pick.deposit, fee = pick.fee })
end)

-- ── Return ────────────────────────────────────────────────────
V.Callback('v-rentals:returnCar', function(src, resolve, data)
    if type(data) ~= 'table' then resolve(false) return end
    local point = pointById(tostring(data.point or ''))
    if not point then resolve({ error = 'point' }) return end
    if not nearPoint(src, point) then resolve({ error = 'far' }) return end

    local p = Core.GetPlayer(src)
    if not p then resolve(false) return end

    local row = MySQL.single.await(
        'SELECT * FROM vehicle_rentals WHERE citizenid = ? AND state = ?', { p.citizenid, 'active' })
    if not row then resolve({ error = 'norental' }) return end

    -- The VEHICLE has to be here, not just the player: re-read the entity from the net
    -- id the client sent and measure it server-side.
    local ent = data.netid and NetworkGetEntityFromNetworkId(tonumber(data.netid) or 0) or 0
    if not ent or ent == 0 or not DoesEntityExist(ent) then resolve({ error = 'novehicle' }) return end
    if GetVehicleNumberPlateText(ent):gsub('%s+$', '') ~= row.plate then
        resolve({ error = 'novehicle' }) return
    end
    if #(GetEntityCoords(ent) - vector3(point.x + 0.0, point.y + 0.0, point.z + 0.0))
       > (num(V.Setting('distance', Config.Distance), Config.Distance) + 8.0) then
        resolve({ error = 'far' }) return
    end

    local late = MySQL.scalar.await(
        'SELECT 1 FROM vehicle_rentals WHERE plate = ? AND expires_at < NOW()', { row.plate })
    local refund = 0
    if not late and V.SettingBool('refundOnTime', Config.RefundOnTime) then
        refund = math.max(0, math.floor(num(row.deposit)))
        p.AddMoney('bank', refund, 'rental-deposit-refund')
    end

    DeleteEntity(ent)
    Live[row.plate] = nil
    V.Use('v-vehicles').RemoveKeys(src, row.plate)
    MySQL.update.await('UPDATE vehicle_rentals SET state = ?, returned_at = NOW() WHERE plate = ?',
        { late and 'late' or 'returned', row.plate })

    Core.Log('vehicles', ('%s returned rental %s (refund %d)'):format(p.citizenid, row.plate, refund),
        nil, p.citizenid)
    resolve({ ok = true, refund = refund, late = late and true or false })
end)

-- ── Expiry ────────────────────────────────────────────────────
-- Runs on its own clock rather than a per-rental timer: a timer dies with a restart, a
-- row does not, so an expiry survives the server going down mid-hire.
local warned = {}

CreateThread(function()
    while GetResourceState('oxmysql') ~= 'started' do Wait(100) end
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS `vehicle_rentals` (
        `plate` VARCHAR(12) NOT NULL,
        `citizenid` VARCHAR(32) NOT NULL,
        `model` VARCHAR(50) NOT NULL,
        `point` VARCHAR(40) NOT NULL,
        `deposit` INT NOT NULL DEFAULT 0,
        `fee` INT NOT NULL DEFAULT 0,
        `started_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        `expires_at` DATETIME NOT NULL,
        `returned_at` DATETIME DEFAULT NULL,
        `state` VARCHAR(12) NOT NULL DEFAULT 'active',   -- active | returned | late | forfeited
        PRIMARY KEY (`plate`), KEY `cid_idx` (`citizenid`, `state`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])

    -- A hire that was live when the server went down has no entity any more. Close it as
    -- forfeited rather than leaving a row that blocks the player from ever hiring again.
    local orphans = MySQL.update.await(
        "UPDATE vehicle_rentals SET state = 'forfeited', returned_at = NOW() WHERE state = 'active'") or 0
    if orphans > 0 then
        print(('[v-rentals] closed %d rental(s) orphaned by a restart'):format(orphans))
    end

    while true do
        Wait(30000)
        local warnAt = math.floor(num(V.Setting('warnAt', Config.WarnAt), Config.WarnAt))

        if warnAt > 0 then
            for _, r in ipairs(MySQL.query.await(
                'SELECT plate, citizenid FROM vehicle_rentals WHERE state = ? AND expires_at > NOW() ' ..
                'AND expires_at <= DATE_ADD(NOW(), INTERVAL ? MINUTE)', { 'active', warnAt }) or {}) do
                if not warned[r.plate] then
                    warned[r.plate] = true
                    local tgt = Core.GetPlayerByCitizenId and Core.GetPlayerByCitizenId(r.citizenid)
                    if tgt then
                        Core.Notify(tgt.source, (L(tgt.source, 'rent.warn')):format(warnAt), 'warning')
                    end
                end
            end
        end

        for _, r in ipairs(MySQL.query.await(
            'SELECT plate, citizenid, deposit FROM vehicle_rentals WHERE state = ? AND expires_at <= NOW()',
            { 'active' }) or {}) do
            MySQL.update.await('UPDATE vehicle_rentals SET state = ?, returned_at = NOW() WHERE plate = ?',
                { 'forfeited', r.plate })
            warned[r.plate] = nil
            local live = Live[r.plate]
            if live and DoesEntityExist(live.entity) then DeleteEntity(live.entity) end
            Live[r.plate] = nil
            local tgt = Core.GetPlayerByCitizenId and Core.GetPlayerByCitizenId(r.citizenid)
            if tgt then Core.Notify(tgt.source, L(tgt.source, 'rent.expired'), 'error') end
            Core.Log('vehicles', ('rental %s expired, deposit %d forfeited'):format(r.plate, r.deposit),
                nil, r.citizenid)
        end
    end
end)

-- ── Boot ──────────────────────────────────────────────────────
V.Ready(function(core)
    Core = core

    -- Seed the points, then the hire rates onto the catalogue. Rates are applied ONLY to
    -- rows that have never had one, so an operator's edits are never overwritten.
    local tries = 0
    while GetResourceState('v-world') == 'started' and not exports['v-world']:IsReady() and tries < 100 do
        Wait(100); tries = tries + 1
    end
    if GetResourceState('v-world') == 'started' then
        exports['v-world']:SeedRentals(Config.Points)
        for cat, rate in pairs(Config.SeedRates or {}) do
            MySQL.update.await(
                'UPDATE vehicle_catalogue SET rent_deposit = ?, rent_fee = ? WHERE cat = ? AND rent_deposit IS NULL',
                { rate[1], rate[2], cat })
        end
        loadPoints()
    end
end)

exports('GetActive', function(cid)
    return MySQL.single.await('SELECT * FROM vehicle_rentals WHERE citizenid = ? AND state = ?',
        { cid, 'active' })
end)

exports('IsRental', function(plate)
    return Live[tostring(plate or '')] ~= nil
end)
