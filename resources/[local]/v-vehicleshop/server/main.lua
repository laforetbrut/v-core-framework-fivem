-- v-vehicleshop | server
-- Dealerships. The purchase is the sensitive part: it must charge and mint the vehicle
-- row as one atomic step, and it must never leave a player who paid without a car (or a
-- player with a car who did not pay).
local Core = exports['v-core']:GetCore()

local Dealers = Config.Dealers      -- runtime lists (DB, or config fallback)
local Cat     = Config.Catalogue
local buying  = {}                  -- src -> true, one purchase in flight per player

-- ── Runtime data ───────────────────────────────────────────────
local function ready()
    return GetResourceState('v-world') == 'started' and exports['v-world']:IsReady()
end

local function rebuild()
    if ready() then
        local d = {}
        for _, r in ipairs(exports['v-world']:GetDealers() or {}) do
            if r.enabled == 1 then d[#d + 1] = r end
        end
        if #d > 0 then Dealers = d end

        local c = {}
        for _, r in ipairs(exports['v-world']:GetVehicleCatalogue() or {}) do
            if r.enabled == 1 then c[#c + 1] = r end
        end
        if #c > 0 then Cat = c end
    end
    TriggerClientEvent('v-vehicleshop:client:dealers', -1, Dealers)
end

local function dealerById(id)
    for _, d in ipairs(Dealers) do if d.id == id then return d end end
end

local function catByModel(model)
    for _, v in ipairs(Cat) do if v.model == model then return v end end
end

--- Does this dealer sell that category? An empty `cats` means "everything".
local function dealerSells(d, cat)
    local list = tostring(d.cats or '')
    if list == '' then return true end
    for c in list:gmatch('[^,%s]+') do
        if c == cat then return true end
    end
    return false
end

--- Is `src` at this dealership, and allowed to use it?
local function atDealer(src, d)
    if not d then return false, 'unknown' end
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return false, 'far' end
    if #(GetEntityCoords(ped) - vector3(d.x + 0.0, d.y + 0.0, d.z + 0.0)) > (Config.Distance + 4.0) then
        return false, 'far'
    end
    if d.job and d.job ~= '' then
        local p = Core.GetPlayer(src)
        local job = p and p.job                        -- { name, grade }
        if not job or job.name ~= d.job then return false, 'nojob' end
    end
    return true
end

--- Which licence a catalogue row needs. The row may override it; otherwise the shop
--- CATEGORY decides. Category rather than GTA vehicle class on purpose: the server has no
--- entity to read a class from, and the category is exactly the human grouping a licence
--- maps to anyway (bikes -> motorcycle, trucks -> HGV, boats -> boating).
local function licenseFor(row)
    if row.license and row.license ~= '' then return row.license end
    return Config.CategoryLicense[row.cat] or Config.DefaultLicense
end

-- ── Browse ─────────────────────────────────────────────────────
Core.RegisterCallback('v-vehicleshop:open', function(source, resolve, data)
    local d = dealerById(type(data) == 'table' and tostring(data.dealer or '') or '')
    local ok, why = atDealer(source, d)
    if not ok then resolve({ error = why }); return end
    local p = Core.GetPlayer(source)
    if not p then resolve(false); return end

    local rows, cats = {}, {}
    for _, v in ipairs(Cat) do
        if dealerSells(d, v.cat) and (v.stock == nil or v.stock ~= 0) then
            local lic = licenseFor(v)
            local jobOk = (not v.job or v.job == '')
                or (p.job and p.job.name == v.job)
            rows[#rows + 1] = {
                model = v.model, label = v.label, cat = v.cat,
                price = v.price, stock = v.stock,
                license = lic,
                hasLicense = (not lic) or (GetResourceState('v-licenses') ~= 'started')
                    or exports['v-licenses']:Has(source, lic),
                jobOk = jobOk, job = v.job,
            }
            cats[v.cat] = true
        end
    end
    local catList = {}
    for _, c in ipairs(Config.Categories) do if cats[c] then catList[#catList + 1] = c end end

    resolve({
        dealer = { id = d.id, label = d.label },
        rows = rows, cats = catList,
        cash = p.money.cash, bank = p.money.bank,
        testSeconds = Config.TestDrive.seconds,
    })
end)

-- ── Buy ────────────────────────────────────────────────────────
Core.RegisterCallback('v-vehicleshop:buy', function(source, resolve, data)
    if type(data) ~= 'table' then resolve(false); return end
    -- one purchase in flight per player: two clicks must not mint two cars
    if buying[source] then resolve({ error = 'busy' }); return end
    buying[source] = true

    local function done(res) buying[source] = nil; resolve(res) end

    local d = dealerById(tostring(data.dealer or ''))
    local ok, why = atDealer(source, d)
    if not ok then done({ error = why }); return end

    local p = Core.GetPlayer(source)
    local model = tostring(data.model or ''):lower()
    local row = catByModel(model)
    if not p or not row then done({ error = 'unknown' }); return end
    if not dealerSells(d, row.cat) then done({ error = 'notsold' }); return end
    if row.stock ~= nil and row.stock == 0 then done({ error = 'nostock' }); return end

    -- job restriction (a police cruiser is not a walk-in purchase)
    if row.job and row.job ~= '' then
        local job = p.job
        if not job or job.name ~= row.job then done({ error = 'nojob' }); return end
    end

    -- licence gate: re-asked here, never trusted from the browse payload
    local lic = licenseFor(row)
    if lic and GetResourceState('v-licenses') == 'started' and not exports['v-licenses']:Has(source, lic) then
        done({ error = 'nolicense', license = lic }); return
    end

    local price = math.max(0, math.floor(tonumber(row.price) or 0))
    local account = (data.account == 'bank') and 'bank' or 'cash'
    if (p.money[account] or 0) < price then done({ error = 'funds' }); return end

    -- Mint the vehicle FIRST: if the row cannot be created we have charged nobody.
    local plate, err = exports['v-vehicles']:CreateOwned(p.citizenid, model, Config.DefaultGarage or 'legion')
    if not plate then done({ error = err or 'unknown' }); return end

    if price > 0 and not p.RemoveMoney(account, price, 'vehicle-buy') then
        -- charge failed after the row existed: delete it rather than gift a car
        MySQL.query.await('DELETE FROM character_vehicles WHERE plate = ?', { plate })
        done({ error = 'funds' }); return
    end

    if row.stock ~= nil and row.stock > 0 then
        MySQL.update.await('UPDATE vehicle_catalogue SET stock = stock - 1 WHERE model = ? AND stock > 0', { model })
        rebuild()
    end

    Core.Log('vehicles', ('%s bought a %s (%s) for %d at %s'):format(p.citizenid, row.label, plate, price, d.id),
        nil, p.citizenid)
    Core.Notify(source, LP(source, 'shop.bought', row.label, plate), 'success')
    local p2 = Core.GetPlayer(source)
    done({ ok = true, plate = plate, cash = p2.money.cash, bank = p2.money.bank })
end)

-- ── Sell back ──────────────────────────────────────────────────
Core.RegisterCallback('v-vehicleshop:sell', function(source, resolve, data)
    if type(data) ~= 'table' then resolve(false); return end
    local d = dealerById(tostring(data.dealer or ''))
    local ok, why = atDealer(source, d)
    if not ok then resolve({ error = why }); return end

    local p = Core.GetPlayer(source)
    local plate = tostring(data.plate or '')
    if not p or plate == '' then resolve(false); return end

    local veh = exports['v-vehicles']:GetVehicle(plate)
    if not veh or veh.citizenid ~= p.citizenid then resolve({ error = 'notyours' }); return end
    if exports['v-vehicles']:IsLive(plate) then resolve({ error = 'stillout' }); return end

    local row = catByModel(veh.model)
    local base = row and row.price or 0
    -- condition matters: a wreck is worth less than a clean car
    local wear = ((tonumber(veh.engine) or 1000) + (tonumber(veh.body) or 1000)) / 2000.0
    local payout = math.floor(base * Config.SellBackRate * math.max(0.35, math.min(1.0, wear)))

    MySQL.query.await('DELETE FROM character_vehicles WHERE plate = ?', { plate })
    p.AddMoney('bank', payout, 'vehicle-sell')

    Core.Log('vehicles', ('%s sold %s back for %d'):format(p.citizenid, plate, payout), nil, p.citizenid)
    Core.Notify(source, LP(source, 'shop.sold', payout), 'success')
    local p2 = Core.GetPlayer(source)
    resolve({ ok = true, payout = payout, cash = p2.money.cash, bank = p2.money.bank })
end)

--- The cars this player could sell back here (garaged only — you cannot sell a car you
--- are currently driving away in).
Core.RegisterCallback('v-vehicleshop:mine', function(source, resolve, data)
    local d = dealerById(type(data) == 'table' and tostring(data.dealer or '') or '')
    local ok, why = atDealer(source, d)
    if not ok then resolve({ error = why }); return end
    local p = Core.GetPlayer(source)
    if not p then resolve(false); return end

    local out = {}
    for _, v in ipairs(exports['v-vehicles']:GetOwnedByCid(p.citizenid) or {}) do
        if v.state == 1 then   -- garaged
            local row = catByModel(v.model)
            local wear = ((tonumber(v.engine) or 1000) + (tonumber(v.body) or 1000)) / 2000.0
            out[#out + 1] = {
                plate = v.plate, model = v.model,
                label = row and row.label or v.model,
                payout = math.floor((row and row.price or 0) * Config.SellBackRate
                    * math.max(0.35, math.min(1.0, wear))),
                condition = math.floor(wear * 100),
            }
        end
    end
    resolve({ rows = out })
end)

-- ── Boot / live reload ─────────────────────────────────────────
CreateThread(function()
    while GetResourceState('oxmysql') ~= 'started' do Wait(100) end
    local tries = 0
    while GetResourceState('v-world') == 'started' and not ready() and tries < 100 do
        Wait(100); tries = tries + 1
    end
    if ready() then
        exports['v-world']:SeedDealers(Config.Dealers)
        exports['v-world']:SeedVehicleCatalogue(Config.Catalogue)
    end
    rebuild()
end)

AddEventHandler('v-world:server:changed', function(domain)
    if domain == nil or domain == 'dealers' or domain == 'vehcat' then rebuild() end
end)

RegisterNetEvent('v-vehicleshop:server:request', function()
    TriggerClientEvent('v-vehicleshop:client:dealers', source, Dealers)
end)

AddEventHandler('playerDropped', function() buying[source] = nil end)

exports('GetCatalogue', function() return Cat end)
exports('GetDealers', function() return Dealers end)

-- ── Admin-tunable settings ─────────────────────────────────────
local function declareSettings()
    Core.RegisterModule('v-vehicleshop', {
        label = 'Dealerships', category = 'vehicles',
        settings = {
            { key = 'sellBackRate', label = 'Sell-back rate (0-1)',   type = 'number', default = Config.SellBackRate, min = 0, max = 1 },
            { key = 'testSeconds',  label = 'Test drive (seconds)',   type = 'number', default = Config.TestDrive.seconds, min = 10, max = 600, step = 1 },
            { key = 'defaultGarage',label = 'Garage a new car goes to', type = 'string', default = Config.DefaultGarage, maxLength = 40 },
            { key = 'priceMult',    label = 'Global price multiplier', type = 'number', default = 1.0, min = 0.1, max = 10 },
        },
    })
end

local function S(key, fallback) return Core.GetSetting('v-vehicleshop', key, fallback) end

local function applySettings()
    Config.SellBackRate      = S('sellBackRate', Config.SellBackRate)
    Config.TestDrive.seconds = S('testSeconds', Config.TestDrive.seconds)
    Config.DefaultGarage     = S('defaultGarage', Config.DefaultGarage)
end

AddEventHandler('v-core:server:settingChanged', function(mod)
    if mod == 'v-vehicleshop' then applySettings() end
end)

-- Own boot thread: `local function` is only visible after its definition, so this block
-- declares itself rather than being called from a thread higher up the file.
CreateThread(function()
    Wait(2600)
    declareSettings()
    applySettings()
end)

-- ══════════════════════════════════════════════════════════════════
--  Automatic vehicle scan
-- ══════════════════════════════════════════════════════════════════
-- The client enumerates the models it can actually spawn (base game + any addon pack) and
-- sends back what it found. The server keeps only the rows that are NOT already in the
-- catalogue, re-validates every field, and holds the result until an admin imports it.
-- Nothing reaches `vehicle_catalogue` because a client said so.
local scanResults = {}     -- src -> { rows, at }

local VALID_CAT = {}
for _, c in ipairs(Config.Categories) do VALID_CAT[c] = true end

RegisterNetEvent('v-vehicleshop:server:scanResult', function(rows)
    local src = source
    if not Core.HasPermission(src, 'admin') or type(rows) ~= 'table' then return end

    local known = {}
    for _, v in ipairs(Cat) do known[v.model] = true end
    -- a model already owned by somebody is known too, even if it left the catalogue
    for _, r in ipairs(MySQL.query.await('SELECT DISTINCT model FROM character_vehicles') or {}) do
        known[r.model] = true
    end

    local out, seen = {}, {}
    for _, r in ipairs(rows) do
        if type(r) == 'table' then
            local model = tostring(r.model or ''):lower():gsub('[^%w_]', ''):sub(1, 50)
            local cat = tostring(r.cat or '')
            if model ~= '' and not known[model] and not seen[model] and VALID_CAT[cat] then
                seen[model] = true
                out[#out + 1] = {
                    model = model,
                    label = tostring(r.label or model):sub(1, 80),
                    cat = cat,
                    price = math.max(1000, math.min(5000000, math.floor(tonumber(r.price) or 20000))),
                    top = math.max(0, math.floor(tonumber(r.top) or 0)),
                    seats = math.max(0, math.min(20, math.floor(tonumber(r.seats) or 0))),
                }
            end
        end
        if #out >= 2000 then break end   -- a scan is a helper, not a bulk-import weapon
    end
    table.sort(out, function(a, b)
        if a.cat ~= b.cat then return a.cat < b.cat end
        return a.label < b.label
    end)

    scanResults[src] = { rows = out, at = os.time() }
    Core.Log('admin', ('vehicle scan: %d new model(s) found'):format(#out), nil, nil)
    TriggerClientEvent('v-vehicleshop:client:scanDone', src, #out)
end)

--- What the last scan found, for the admin panel to review.
Core.RegisterCallback('v-vehicleshop:scanList', function(source, resolve)
    if not Core.HasPermission(source, 'admin') then resolve(false); return end
    local r = scanResults[source]
    resolve({ rows = (r and r.rows) or {}, at = r and r.at or nil, cats = Config.Categories })
end)

--- Import a reviewed selection into the catalogue. The rows are taken from the SERVER's
--- own stored scan, never from the payload — the client only names which models to keep,
--- and may adjust the category and price it was shown.
Core.RegisterCallback('v-vehicleshop:scanImport', function(source, resolve, data)
    if not Core.HasPermission(source, 'admin') or type(data) ~= 'table' then resolve(false); return end
    local stored = scanResults[source]
    if not stored then resolve({ error = 'noscan' }); return end

    local byModel = {}
    for _, r in ipairs(stored.rows) do byModel[r.model] = r end

    local n = 0
    for _, pick in ipairs(data.rows or {}) do
        local base = type(pick) == 'table' and byModel[tostring(pick.model or '')] or nil
        if base then
            local cat = VALID_CAT[tostring(pick.cat or '')] and pick.cat or base.cat
            local price = math.max(1000, math.min(5000000, math.floor(tonumber(pick.price) or base.price)))
            MySQL.insert.await([[INSERT IGNORE INTO vehicle_catalogue (model, label, cat, price, stock, license, job, enabled)
                VALUES (?,?,?,?,-1,NULL,NULL,1)]], { base.model, base.label, cat, price })
            n = n + 1
        end
    end

    if n > 0 then
        exports['v-world']:RefreshDomain('vehcat')
        rebuild()
    end
    local p = Core.GetPlayer(source)
    Core.Log('admin', ('imported %d vehicle(s) into the catalogue'):format(n), nil, p and p.citizenid or nil)
    resolve({ ok = true, imported = n })
end)

AddEventHandler('playerDropped', function() scanResults[source] = nil end)
