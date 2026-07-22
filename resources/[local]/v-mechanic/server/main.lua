-- v-mechanic | server
-- Owns the per-part condition, the odometer and the repair economy.
--
-- Wear is *observed* by the client (it is the only side that knows how the car is being
-- driven) but every number that lands in the DB is clamped here, and every repair is
-- priced, paid and consumed here. The client can under-report its own wear; it cannot
-- invent condition, skip a payment, or repair a part it does not have.
local Core = exports['v-core']:GetCore()

local Shops = Config.Shops        -- runtime list (DB, or config fallback)
local PartsByKey, PartsEVByKey = {}, {}
for _, p in ipairs(Config.Parts)   do PartsByKey[p.key]   = p end
for _, p in ipairs(Config.PartsEV) do PartsEVByKey[p.key] = p end

local function partSet(isEV) return isEV and Config.PartsEV or Config.Parts end
local function partDef(key, isEV) return (isEV and PartsEVByKey or PartsByKey)[key] end

-- ── Shops ──────────────────────────────────────────────────────
local function rebuildShops()
    local rows = (GetResourceState('v-world') == 'started' and exports['v-world']:IsReady())
        and exports['v-world']:GetMechShops() or nil
    local list = {}
    for _, r in ipairs(rows or {}) do
        if r.enabled == 1 then list[#list + 1] = r end
    end
    if #list == 0 then list = Config.Shops end
    Shops = list
    TriggerClientEvent('v-mechanic:client:shops', -1, Shops)
end

local function shopById(id)
    for _, sh in ipairs(Shops) do if sh.id == id then return sh end end
end

--- Is `src` at this shop, and is anyone qualified to work there?
--- Returns ok, reason, labourMultiplier.
local function atShop(src, sh)
    if not sh then return false, 'unknown' end
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return false, 'far' end
    if #(GetEntityCoords(ped) - vector3(sh.x + 0.0, sh.y + 0.0, sh.z + 0.0)) > (Config.Distance + 4.0) then
        return false, 'far'
    end
    local mult = (tonumber(sh.mult) or 1.0) * Config.LabourMult
    if sh.job and sh.job ~= '' then
        local p = Core.GetPlayer(src)
        local job = p and p.job                      -- { name, grade }
        -- a staffed shop is cheap for its own mechanics and self-service for everyone else
        if not job or job.name ~= sh.job then mult = mult * Config.SelfServMult end
    end
    return true, nil, mult
end

-- ── Part state on the row ──────────────────────────────────────
local function readParts(row, isEV)
    local t = row and row.parts
    if type(t) == 'string' then t = json.decode(t) end
    t = (type(t) == 'table') and t or {}
    local out = {}
    for _, def in ipairs(partSet(isEV)) do
        local v = tonumber(t[def.key])
        out[def.key] = math.max(0, math.min(100, v or 100))
    end
    return out
end

local function isElectric(model)
    -- the client knows the ped-side truth; server-side we mirror v-fuel's model list
    if GetResourceState('v-fuel') ~= 'started' then return false end
    for _, m in ipairs(exports['v-fuel']:GetElectricModels() or {}) do
        if m == tostring(model or ''):lower() then return true end
    end
    return false
end

-- ── Client reports wear ────────────────────────────────────────
-- The client sends the DELTAS it observed. We only ever subtract, never add: a client
-- cannot heal a part by reporting a negative delta, and the total is clamped to [0,100].
RegisterNetEvent('v-mechanic:server:reportWear', function(plate, deltas, mileage)
    local src = source
    if type(plate) ~= 'string' or type(deltas) ~= 'table' then return end
    if not exports['v-vehicles']:HasKeys(src, plate) then return end

    local row = exports['v-vehicles']:GetVehicle(plate)
    if not row then return end
    local isEV = isElectric(row.model)
    local parts = readParts(row, isEV)

    for key, d in pairs(deltas) do
        local def = partDef(key, isEV)
        local drop = tonumber(d)
        if def and drop and drop > 0 then
            -- a single report can never take more than 25 points off a part: a broken or
            -- hostile client cannot total a car in one message
            parts[key] = math.max(0, parts[key] - math.min(25, drop))
        end
    end

    local km = math.max(tonumber(row.mileage) or 0,
                        math.min((tonumber(row.mileage) or 0) + 500, tonumber(mileage) or 0))
    MySQL.update.await('UPDATE character_vehicles SET parts = ?, mileage = ? WHERE plate = ?',
        { json.encode(parts), km, plate })
end)

-- ── Diagnostics ────────────────────────────────────────────────
Core.RegisterCallback('v-mechanic:diagnose', function(source, resolve, data)
    local p = Core.GetPlayer(source)
    local plate = type(data) == 'table' and tostring(data.plate or '') or ''
    if not p or plate == '' then resolve(false); return end

    local row = exports['v-vehicles']:GetVehicle(plate)
    if not row then resolve({ error = 'unknown' }); return end

    -- Reading a car needs either the scanner or a shop to stand in.
    local sh = data.shop and shopById(tostring(data.shop)) or nil
    local mult = 1.0
    if sh then
        local ok, why, m = atShop(source, sh)
        if not ok then resolve({ error = why }); return end
        mult = m
    elseif exports['v-inventory']:GetItemCount(source, Config.DiagTool) < 1 then
        resolve({ error = 'notool' }); return
    end

    local isEV = isElectric(row.model)
    local parts = readParts(row, isEV)
    local out = {}
    for _, def in ipairs(partSet(isEV)) do
        out[#out + 1] = {
            key = def.key, i18n = def.i18n, affects = def.affects, item = def.item,
            condition = math.floor(parts[def.key] + 0.5),
            labour = math.ceil((def.labour or 0) * mult),
            have = exports['v-inventory']:GetItemCount(source, def.item),
        }
    end
    resolve({
        plate = plate, model = row.model, ev = isEV,
        mileage = math.floor(tonumber(row.mileage) or 0),
        service = math.floor(tonumber(row.last_service) or 0),
        interval = Config.Odometer.service,
        parts = out, shop = sh and { id = sh.id, label = sh.label } or nil,
        cash = p.money.cash, bank = p.money.bank,
        kit = exports['v-inventory']:GetItemCount(source, Config.RepairKit),
    })
end)

-- ── Replace a part (shop) ──────────────────────────────────────
Core.RegisterCallback('v-mechanic:replace', function(source, resolve, data)
    if type(data) ~= 'table' then resolve(false); return end
    local sh = shopById(tostring(data.shop or ''))
    local ok, why, mult = atShop(source, sh)
    if not ok then resolve({ error = why }); return end

    local p = Core.GetPlayer(source)
    local plate = tostring(data.plate or '')
    local key = tostring(data.part or '')
    if not p or plate == '' or key == '' then resolve(false); return end

    local row = exports['v-vehicles']:GetVehicle(plate)
    if not row then resolve({ error = 'unknown' }); return end
    local isEV = isElectric(row.model)
    local def = partDef(key, isEV)
    if not def then resolve({ error = 'unknown' }); return end

    local parts = readParts(row, isEV)
    if parts[key] >= 99 then resolve({ error = 'notworn' }); return end

    -- The part itself comes out of the inventory; the labour is paid.
    if exports['v-inventory']:GetItemCount(source, def.item) < 1 then
        resolve({ error = 'nopart' }); return
    end
    local labour = math.ceil((def.labour or 0) * mult)
    local account = (data.account == 'bank') and 'bank' or 'cash'
    if labour > 0 and (p.money[account] or 0) < labour then resolve({ error = 'funds' }); return end
    if not exports['v-inventory']:RemoveItem(source, def.item, 1) then
        resolve({ error = 'nopart' }); return
    end
    if labour > 0 and not p.RemoveMoney(account, labour, 'mechanic-' .. key) then
        exports['v-inventory']:AddItem(source, def.item, 1)   -- never keep the part on a failed charge
        resolve({ error = 'funds' }); return
    end

    parts[key] = 100
    MySQL.update.await('UPDATE character_vehicles SET parts = ? WHERE plate = ?', { json.encode(parts), plate })
    TriggerClientEvent('v-mechanic:client:partsChanged', -1, plate, parts)

    Core.Log('mechanic', ('%s replaced %s on %s for %d'):format(p.citizenid, key, plate, labour), nil, p.citizenid)
    Core.Notify(source, LP(source, 'mech.replaced', LP(source, def.i18n)), 'success')
    local p2 = Core.GetPlayer(source)
    resolve({ ok = true, parts = parts, cash = p2.money.cash, bank = p2.money.bank })
end)

-- ── Field patch with a repair kit ──────────────────────────────
-- Deliberately worse than a shop: it tops a part up to KitRestore and refuses a part that
-- is already too far gone. A kit is a way home, not a free garage.
Core.RegisterCallback('v-mechanic:patch', function(source, resolve, data)
    local p = Core.GetPlayer(source)
    local plate = type(data) == 'table' and tostring(data.plate or '') or ''
    local key = type(data) == 'table' and tostring(data.part or '') or ''
    if not p or plate == '' or key == '' then resolve(false); return end
    if not exports['v-vehicles']:HasKeys(source, plate) then resolve({ error = 'notyours' }); return end

    local row = exports['v-vehicles']:GetVehicle(plate)
    if not row then resolve({ error = 'unknown' }); return end
    local isEV = isElectric(row.model)
    if not partDef(key, isEV) then resolve({ error = 'unknown' }); return end

    local parts = readParts(row, isEV)
    if parts[key] >= Config.KitRestore then resolve({ error = 'notworn' }); return end
    if parts[key] < Config.KitMinimum then resolve({ error = 'toobroken' }); return end
    if not exports['v-inventory']:RemoveItem(source, Config.RepairKit, 1) then
        resolve({ error = 'nokit' }); return
    end

    parts[key] = Config.KitRestore
    MySQL.update.await('UPDATE character_vehicles SET parts = ? WHERE plate = ?', { json.encode(parts), plate })
    TriggerClientEvent('v-mechanic:client:partsChanged', -1, plate, parts)
    Core.Notify(source, LP(source, 'mech.patched'), 'success')
    resolve({ ok = true, parts = parts })
end)

-- ── Full service ───────────────────────────────────────────────
-- Resets the service counter and tops up the consumables (filters, plugs, fluids) in one
-- go — the routine maintenance that stops wear accelerating.
Core.RegisterCallback('v-mechanic:service', function(source, resolve, data)
    if type(data) ~= 'table' then resolve(false); return end
    local sh = shopById(tostring(data.shop or ''))
    local ok, why, mult = atShop(source, sh)
    if not ok then resolve({ error = why }); return end

    local p = Core.GetPlayer(source)
    local plate = tostring(data.plate or '')
    if not p or plate == '' then resolve(false); return end
    local row = exports['v-vehicles']:GetVehicle(plate)
    if not row then resolve({ error = 'unknown' }); return end

    local isEV = isElectric(row.model)
    local parts = readParts(row, isEV)
    local consumables = isEV and { 'coolant_ev' } or { 'airfilter', 'oilfilter', 'sparkplugs' }
    local cost = 0
    for _, key in ipairs(consumables) do
        local def = partDef(key, isEV)
        if def and parts[key] < 100 then cost = cost + (def.labour or 0) end
    end
    cost = math.ceil(cost * mult)
    local account = (data.account == 'bank') and 'bank' or 'cash'
    if cost > 0 and not p.RemoveMoney(account, cost, 'mechanic-service') then
        resolve({ error = 'funds' }); return
    end
    for _, key in ipairs(consumables) do
        if parts[key] ~= nil then parts[key] = 100 end
    end
    local km = math.floor(tonumber(row.mileage) or 0)
    MySQL.update.await('UPDATE character_vehicles SET parts = ?, last_service = ? WHERE plate = ?',
        { json.encode(parts), km, plate })
    TriggerClientEvent('v-mechanic:client:partsChanged', -1, plate, parts)

    Core.Log('mechanic', ('%s serviced %s for %d'):format(p.citizenid, plate, cost), nil, p.citizenid)
    Core.Notify(source, LP(source, 'mech.serviced', cost), 'success')
    local p2 = Core.GetPlayer(source)
    resolve({ ok = true, parts = parts, service = km, cash = p2.money.cash, bank = p2.money.bank })
end)

-- A vehicle just entered the world: hand its driver the condition so the client can
-- start applying the penalties immediately instead of waiting for the first diagnostic.
AddEventHandler('v-vehicles:server:spawned', function(src, plate, _, row)
    if not row then return end
    local isEV = isElectric(row.model)
    TriggerClientEvent('v-mechanic:client:state', src, plate, readParts(row, isEV),
        tonumber(row.mileage) or 0, tonumber(row.last_service) or 0)
end)

-- The scanner is an item: using it reads whatever vehicle you are next to.
CreateThread(function()
    while GetResourceState('v-inventory') ~= 'started' do Wait(200) end
    exports['v-inventory']:RegisterUsableItem(Config.DiagTool, function(src)
        TriggerClientEvent('v-mechanic:client:scan', src)
    end)
end)

-- ── Boot ───────────────────────────────────────────────────────
CreateThread(function()
    while GetResourceState('oxmysql') ~= 'started' do Wait(100) end
    local tries = 0
    while GetResourceState('v-world') == 'started' and not exports['v-world']:IsReady() and tries < 100 do
        Wait(100); tries = tries + 1
    end
    if GetResourceState('v-world') == 'started' and exports['v-world']:IsReady() then
        exports['v-world']:SeedMechShops(Config.Shops)
    end
    rebuildShops()
end)

AddEventHandler('v-world:server:changed', function(domain)
    if domain == nil or domain == 'mechshops' then rebuildShops() end
end)

RegisterNetEvent('v-mechanic:server:request', function()
    TriggerClientEvent('v-mechanic:client:shops', source, Shops)
end)

-- Other modules ask for a plate's condition (v-fuel scales EV capacity by it).
exports('GetParts', function(plate)
    local row = exports['v-vehicles']:GetVehicle(plate)
    if not row then return nil end
    return readParts(row, isElectric(row.model))
end)
exports('GetShops', function() return Shops end)

-- ── Admin-tunable settings ─────────────────────────────────────
local function declareSettings()
    Core.RegisterModule('v-mechanic', {
        label = 'Mechanic & wear', category = 'vehicles',
        settings = {
            { key = 'wearPer100km', label = 'Wear per 100 km',          type = 'number', default = Config.WearPer100km, min = 0, max = 50 },
            { key = 'degradeBelow', label = 'Degrade below (%)',        type = 'number', default = Config.DegradeBelow, min = 0, max = 100, step = 1 },
            { key = 'warnBelow',    label = 'Warn below (%)',           type = 'number', default = Config.WarnBelow, min = 0, max = 100, step = 1 },
            { key = 'kitRestore',   label = 'Repair kit restores to (%)', type = 'number', default = Config.KitRestore, min = 0, max = 100, step = 1 },
            { key = 'labourMult',   label = 'Labour price multiplier',  type = 'number', default = Config.LabourMult, min = 0.1, max = 5 },
            { key = 'selfServMult', label = 'Self-service multiplier',  type = 'number', default = Config.SelfServMult, min = 1, max = 5 },
            { key = 'serviceEvery', label = 'Service interval (km)',    type = 'number', default = Config.Odometer.service, min = 100, max = 100000, step = 1 },
        },
    })
end

local function S(key, fallback) return Core.GetSetting('v-mechanic', key, fallback) end

local function applySettings()
    Config.WearPer100km     = S('wearPer100km', Config.WearPer100km)
    Config.DegradeBelow     = S('degradeBelow', Config.DegradeBelow)
    Config.WarnBelow        = S('warnBelow', Config.WarnBelow)
    Config.KitRestore       = S('kitRestore', Config.KitRestore)
    Config.LabourMult       = S('labourMult', Config.LabourMult)
    Config.SelfServMult     = S('selfServMult', Config.SelfServMult)
    Config.Odometer.service = S('serviceEvery', Config.Odometer.service)
    -- the client owns the wear observation, so it needs the same numbers
    TriggerClientEvent('v-mechanic:client:tunables', -1, {
        wearPer100km = Config.WearPer100km, degradeBelow = Config.DegradeBelow,
        warnBelow = Config.WarnBelow, service = Config.Odometer.service,
    })
end

AddEventHandler('v-core:server:settingChanged', function(mod)
    if mod == 'v-mechanic' then applySettings() end
end)

-- Own boot thread: `local function` is only visible after its definition, so this block
-- declares itself rather than being called from a thread higher up the file.
CreateThread(function()
    Wait(2600)
    declareSettings()
    applySettings()
end)
