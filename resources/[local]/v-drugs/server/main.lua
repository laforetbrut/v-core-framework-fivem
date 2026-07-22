-- v-drugs | server
-- The illegal loop already shipped as a static chain: fixed gather nodes, a craft bench
-- and a buyer who always pays the same. This adds the two parts that make it a game -
-- plantations a player places and can lose, and street dealing that pushes back.
--
-- Nothing here trusts the client. Plant positions, growth, yields, prices, demand and heat
-- are all derived server-side; the client sends "I want to plant here" and nothing else.

local Core
local Drugs = {}         -- [key] = row
local Plants = {}        -- [id] = row, mirrored to clients
local Heat = {}          -- [citizenid] = number
local Demand = {}        -- [district] = 0..1
local LastSale = {}      -- [source] = GetGameTimer()

local function num(v, d) return tonumber(v) or d or 0 end

local function L(src, k)
    local p = Core and Core.GetPlayer(src)
    local lang = (p and p.lang) or 'fr'
    return (Locales[lang] or Locales.fr or {})[k] or k
end

-- ── Settings ──────────────────────────────────────────────────
V.Module({
    label = 'Drugs', category = 'gameplay',
    settings = {
        { key = 'planting',    label = 'Planting enabled',        type = 'bool',   default = true },
        { key = 'maxPlants',   label = 'Plants per player',       type = 'number', default = Config.Plant.maxPerPlayer, min = 1, max = 50, step = 1 },
        { key = 'minApart',    label = 'Minimum spacing (m)',     type = 'number', default = Config.Plant.minApart, min = 1, max = 50, step = 0.5 },
        { key = 'stealMult',   label = 'Share a thief gets',      type = 'number', default = Config.Plant.stealMult, min = 0, max = 1, step = 0.05 },
        { key = 'growMult',    label = 'Growth speed multiplier', type = 'number', default = 1.0, min = 0.1, max = 10, step = 0.1 },
        { key = 'dealing',     label = 'Street dealing enabled',  type = 'bool',   default = true },
        { key = 'priceMult',   label = 'Street price multiplier', type = 'number', default = 1.0, min = 0, max = 10, step = 0.05 },
        { key = 'demandDrop',  label = 'Demand lost per sale',    type = 'number', default = Config.Street.demandDrop, min = 0, max = 1, step = 0.01 },
        { key = 'demandRecover', label = 'Demand regained per minute', type = 'number', default = Config.Street.demandRecover, min = 0, max = 1, step = 0.01 },
        { key = 'turfBonus',   label = 'Bonus on your own turf',  type = 'number', default = Config.Street.turfBonus, min = 0, max = 2, step = 0.05 },
        { key = 'heatDecay',   label = 'Heat lost per minute',    type = 'number', default = Config.Heat.decayPerMin, min = 0, max = 50, step = 0.5 },
        { key = 'bustBase',    label = 'Bust chance at no heat',  type = 'number', default = Config.Heat.bustBase, min = 0, max = 1, step = 0.01 },
        { key = 'bustMax',     label = 'Bust chance at max heat', type = 'number', default = Config.Heat.bustAtMax, min = 0, max = 1, step = 0.01 },
        { key = 'alertPolice', label = 'A bust alerts the police', type = 'bool',  default = Config.Heat.alertPolice },
        { key = 'dirtyMoney',  label = 'Street sales pay dirty money', type = 'bool', default = true },
    },
})

-- ── Substances ────────────────────────────────────────────────
local function loadDrugs()
    Drugs = {}
    if GetResourceState('v-world') ~= 'started' then return end
    for _, d in ipairs(exports['v-world']:GetDrugs() or {}) do
        if d.enabled ~= false then Drugs[d.key] = d end
    end
end

--- Which substance does this item belong to, and what does a unit of it fetch?
local function productOf(item)
    for _, d in pairs(Drugs) do
        if d.product_item == item then return d, 1.0 end
    end
    -- Refined forms are not their own substance row: they map back to one through the
    -- multiplier table, so adding a baggy does not mean adding a whole substance.
    local mult = Config.ProductMult[item]
    if mult then
        local stem = item:match('^([a-z]+)_') or ''
        for key, d in pairs(Drugs) do
            if key:sub(1, #stem) == stem or stem:sub(1, #key) == key then return d, mult end
        end
    end
    return nil, 0
end

-- ── Plants ────────────────────────────────────────────────────
--- Forward-declared: pushPlants decorates rows with a stage the client cannot derive
--- (grow time lives on world_drugs, not on the plant row).
local plantStage, plantHealth

local function pushPlants(src)
    local out = {}
    for id, r in pairs(Plants) do
        local stage = plantStage(r)
        out[id] = {
            id = r.id, drug = r.drug, x = r.x, y = r.y, z = r.z,
            pct = math.floor(stage * 100),
            health = math.floor(plantHealth(r)),
        }
    end
    TriggerClientEvent('v-drugs:client:plants', src or -1, out)
end

local function loadPlants()
    Plants = {}
    for _, r in ipairs(MySQL.query.await('SELECT * FROM drug_plants') or {}) do
        Plants[r.id] = r
    end
    pushPlants()
end

--- Growth is derived from timestamps rather than ticked, so a server restart mid-grow
--- loses nothing and a plant keeps growing while nobody is online.
function plantStage(row)
    local d = Drugs[row.drug]
    if not d then return 0, 0 end
    local grow = math.max(1, num(d.grow_minutes, 60) / math.max(0.1, num(V.Setting('growMult', 1.0), 1.0)))
    local mins = num(row.age_minutes)
    return math.min(1.0, mins / grow), grow
end

--- Health falls while unwatered. A wilted plant still yields, badly: a bad grower is
--- punished rather than wiped.
function plantHealth(row)
    local d = Drugs[row.drug]
    if not d then return 0 end
    local hours = num(row.dry_hours)
    local grace = num(d.water_hours, 2)
    if hours <= grace then return math.min(100, num(row.health, 100)) end
    local lost = (hours - grace) * Config.Water.wiltPerHour
    return math.max(0, math.min(100, num(row.health, 100) - lost))
end

local function refreshPlant(id)
    local r = MySQL.single.await([[SELECT *,
        TIMESTAMPDIFF(MINUTE, planted_at, NOW()) AS age_minutes,
        TIMESTAMPDIFF(HOUR, watered_at, NOW()) AS dry_hours
        FROM drug_plants WHERE id = ?]], { id })
    if r then Plants[id] = r else Plants[id] = nil end
    pushPlants()
    return r
end

V.Callback('v-drugs:plant', function(src, resolve, data)
    if not V.SettingBool('planting', true) then resolve({ error = 'off' }) return end
    if type(data) ~= 'table' then resolve(false) return end
    local p = Core.GetPlayer(src)
    if not p then resolve(false) return end

    local key = tostring(data.drug or '')
    local d = Drugs[key]
    if not d or not d.seed_item then resolve({ error = 'nogrow' }) return end

    -- The position is the PLAYER's, not the payload's: a client that picks its own
    -- coordinates can plant through a wall or on the other side of the map.
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then resolve(false) return end
    local coords = GetEntityCoords(ped)

    local mine = MySQL.scalar.await('SELECT COUNT(*) FROM drug_plants WHERE citizenid = ?', { p.citizenid }) or 0
    local maxP = math.floor(num(V.Setting('maxPlants', Config.Plant.maxPerPlayer), Config.Plant.maxPerPlayer))
    if mine >= maxP then resolve({ error = 'toomany' }) return end

    local apart = num(V.Setting('minApart', Config.Plant.minApart), Config.Plant.minApart)
    for _, r in pairs(Plants) do
        if #(coords - vector3(r.x + 0.0, r.y + 0.0, r.z + 0.0)) < apart then
            resolve({ error = 'tooclose' }) return
        end
    end

    if V.Use('v-inventory').RemoveItem(src, d.seed_item, 1) ~= true then
        resolve({ error = 'noseed' }) return
    end

    local id = MySQL.insert.await([[INSERT INTO drug_plants (citizenid, drug, x, y, z, health)
        VALUES (?,?,?,?,?,100)]], { p.citizenid, key, coords.x, coords.y, coords.z - 0.9 })
    refreshPlant(id)
    Core.Log('drugs', ('%s planted %s'):format(p.citizenid, key), nil, p.citizenid)
    resolve({ ok = true })
end)

V.Callback('v-drugs:water', function(src, resolve, data)
    local row = Plants[tonumber(data and data.id) or 0]
    if not row then resolve({ error = 'noplant' }) return end
    local ped = GetPlayerPed(src)
    if #(GetEntityCoords(ped) - vector3(row.x + 0.0, row.y + 0.0, row.z + 0.0)) > (Config.Distance + 2.0) then
        resolve({ error = 'far' }) return
    end
    if V.Use('v-inventory').RemoveItem(src, Config.Water.item, 1) ~= true then
        resolve({ error = 'nowater' }) return
    end
    local health = math.min(100, plantHealth(row) + Config.Water.healthPerWater)
    MySQL.update.await('UPDATE drug_plants SET watered_at = NOW(), health = ? WHERE id = ?',
        { health, row.id })
    refreshPlant(row.id)
    resolve({ ok = true })
end)

V.Callback('v-drugs:harvest', function(src, resolve, data)
    local row = Plants[tonumber(data and data.id) or 0]
    if not row then resolve({ error = 'noplant' }) return end
    local p = Core.GetPlayer(src)
    if not p then resolve(false) return end

    local ped = GetPlayerPed(src)
    if #(GetEntityCoords(ped) - vector3(row.x + 0.0, row.y + 0.0, row.z + 0.0)) > (Config.Distance + 2.0) then
        resolve({ error = 'far' }) return
    end

    local d = Drugs[row.drug]
    if not d then resolve({ error = 'noplant' }) return end
    local stage = plantStage(row)
    if stage < 1.0 then resolve({ error = 'unripe', pct = math.floor(stage * 100) }) return end

    -- A thief gets a share, and the owner is told. Anonymity would make theft free.
    local theft = row.citizenid ~= p.citizenid
    local health = plantHealth(row)
    local base = math.random(math.floor(num(d.yield_min, 2)), math.max(math.floor(num(d.yield_min, 2)), math.floor(num(d.yield_max, 5))))
    local yield = math.max(1, math.floor(base * (health / 100)))
    if theft then
        yield = math.max(1, math.floor(yield * num(V.Setting('stealMult', Config.Plant.stealMult), Config.Plant.stealMult)))
    end

    if V.Use('v-inventory').AddItem(src, d.product_item, yield) ~= true then
        resolve({ error = 'full' }) return
    end

    MySQL.query.await('DELETE FROM drug_plants WHERE id = ?', { row.id })
    Plants[row.id] = nil
    pushPlants()

    if theft then
        local owner = Core.GetPlayerByCitizenId(row.citizenid)
        if owner then Core.Notify(owner.source, L(owner.source, 'drug.stolen'), 'error') end
        Core.Log('drugs', ('%s stole a %s plant from %s'):format(p.citizenid, row.drug, row.citizenid),
            nil, p.citizenid)
    end
    resolve({ ok = true, amount = yield, theft = theft })
end)

-- ── Heat ──────────────────────────────────────────────────────
local function heatOf(cid) return math.max(0, math.min(Config.Heat.max, num(Heat[cid]))) end

local function addHeat(cid, n)
    Heat[cid] = math.max(0, math.min(Config.Heat.max, heatOf(cid) + n))
end

-- ── Street dealing ────────────────────────────────────────────
--- The district is the gang turf when there is one, and a coarse grid otherwise, so
--- demand is per place rather than global without needing a zone list nobody maintains.
local function districtAt(coords)
    local turf = V.Use('v-gangs').TurfAt(coords)
    if turf then return 'turf:' .. turf end
    return ('grid:%d:%d'):format(math.floor(coords.x / 300), math.floor(coords.y / 300))
end

local function demandFor(district)
    local v = Demand[district]
    if v == nil then v = 1.0; Demand[district] = v end
    return math.max(Config.Street.demandFloor, math.min(1.0, v))
end

V.Callback('v-drugs:sell', function(src, resolve, data)
    if not V.SettingBool('dealing', true) then resolve({ error = 'off' }) return end
    if type(data) ~= 'table' then resolve(false) return end
    local p = Core.GetPlayer(src)
    if not p then resolve(false) return end

    local now = GetGameTimer()
    if LastSale[src] and now - LastSale[src] < Config.Street.cooldown * 1000 then
        resolve({ error = 'wait' }) return
    end

    local item = tostring(data.item or '')
    local d, mult = productOf(item)
    if not d then resolve({ error = 'notdrug' }) return end

    local cid = p.citizenid
    local heat = heatOf(cid)
    if heat >= Config.Street.refuseAtHeat then resolve({ error = 'refused' }) return end

    if V.Use('v-inventory').RemoveItem(src, item, 1) ~= true then resolve({ error = 'noitem' }) return end
    LastSale[src] = now

    local ped = GetPlayerPed(src)
    local coords = GetEntityCoords(ped)
    local district = districtAt(coords)

    -- Price: base, times the product's refinement, times what this district will still
    -- bear, plus a bonus for dealing on your own turf.
    local price = num(d.street_price, 120) * mult
    price = price * demandFor(district)
    price = price * num(V.Setting('priceMult', 1.0), 1.0)
    local ownTurf = V.Use('v-gangs').InOwnTurf(src) == true
    if ownTurf then price = price * (1.0 + num(V.Setting('turfBonus', Config.Street.turfBonus), Config.Street.turfBonus)) end
    price = math.max(1, math.floor(price))

    Demand[district] = math.max(Config.Street.demandFloor,
        demandFor(district) - num(V.Setting('demandDrop', Config.Street.demandDrop), Config.Street.demandDrop))
    addHeat(cid, num(d.heat, 4))

    -- Dirty money by default: it has to go through the launderer, which is what connects
    -- dealing to the banking side rather than paying straight into a clean balance.
    if V.SettingBool('dirtyMoney', true) then
        V.Use('v-inventory').AddItem(src, 'marked_bills', price)
    else
        p.AddMoney('cash', price, 'street-deal')
    end

    -- Getting caught scales with heat, so a long session on one corner is what gets you
    -- arrested, not bad luck on the first sale.
    local base = num(V.Setting('bustBase', Config.Heat.bustBase), Config.Heat.bustBase)
    local top  = num(V.Setting('bustMax', Config.Heat.bustAtMax), Config.Heat.bustAtMax)
    local chance = base + (top - base) * (heatOf(cid) / Config.Heat.max)
    local busted = math.random() < chance

    if busted and V.SettingBool('alertPolice', Config.Heat.alertPolice) then
        for _, sid in ipairs(GetPlayers()) do
            local o = tonumber(sid)
            if o and V.Use('v-police').IsCop(o) == true then
                TriggerClientEvent('v-drugs:client:bustAlert', o, coords, Config.Heat.alertRadius)
            end
        end
        Core.Log('drugs', ('%s was seen dealing (heat %d)'):format(cid, math.floor(heatOf(cid))),
            nil, cid)
    end

    resolve({ ok = true, price = price, heat = math.floor(heatOf(cid)),
              dirty = V.SettingBool('dirtyMoney', true), seen = busted })
end)

V.Callback('v-drugs:heat', function(src, resolve)
    local p = Core.GetPlayer(src)
    resolve(p and math.floor(heatOf(p.citizenid)) or 0)
end)

-- ── Upkeep ────────────────────────────────────────────────────
CreateThread(function()
    while GetResourceState('oxmysql') ~= 'started' do Wait(100) end

    MySQL.query.await([[CREATE TABLE IF NOT EXISTS `drug_plants` (
        `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
        `citizenid` VARCHAR(32) NOT NULL,
        `drug` VARCHAR(30) NOT NULL,
        `x` FLOAT NOT NULL, `y` FLOAT NOT NULL, `z` FLOAT NOT NULL,
        `health` FLOAT NOT NULL DEFAULT 100,
        `planted_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        `watered_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (`id`), KEY `cid_idx` (`citizenid`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])

    while true do
        Wait(60000)
        -- Heat and demand both drift back on their own clock. Nothing is stored: a
        -- restart resetting them is the correct behaviour, since both model the last hour
        -- rather than a permanent record.
        local decay = num(V.Setting('heatDecay', Config.Heat.decayPerMin), Config.Heat.decayPerMin)
        for cid, v in pairs(Heat) do
            local left = v - decay
            Heat[cid] = (left > 0) and left or nil
        end
        local rec = num(V.Setting('demandRecover', Config.Street.demandRecover), Config.Street.demandRecover)
        for district, v in pairs(Demand) do
            if v < 1.0 then Demand[district] = math.min(1.0, v + rec) else Demand[district] = nil end
        end
        -- Re-read the growth clock so clients see plants ripen without an interaction.
        local ok = pcall(function()
            for _, r in ipairs(MySQL.query.await([[SELECT *,
                TIMESTAMPDIFF(MINUTE, planted_at, NOW()) AS age_minutes,
                TIMESTAMPDIFF(HOUR, watered_at, NOW()) AS dry_hours FROM drug_plants]]) or {}) do
                Plants[r.id] = r
            end
        end)
        if ok then pushPlants() end
    end
end)

AddEventHandler('v-world:server:changed', function(domain)
    if domain == nil or domain == 'drugs' then loadDrugs() end
end)

RegisterNetEvent('v-drugs:server:request', function() pushPlants(source) end)

AddEventHandler('playerDropped', function() LastSale[source] = nil end)

V.Ready(function(core)
    Core = core
    local tries = 0
    while GetResourceState('v-world') == 'started' and not exports['v-world']:IsReady() and tries < 100 do
        Wait(100); tries = tries + 1
    end
    if GetResourceState('v-world') == 'started' then
        exports['v-world']:SeedDrugs(Config.Drugs)
        loadDrugs()
    end
    loadPlants()

    -- Planting is done by USING the seed, and offering by USING the drug: that is how
    -- every other consumable in this framework works, so neither needs a command or a menu.
    local inv = V.Use('v-inventory')
    local registered = {}
    for _, d in pairs(Drugs) do
        if d.seed_item then
            local key = d.key
            inv.RegisterUsableItem(d.seed_item, function(src)
                TriggerClientEvent('v-drugs:client:startPlant', src, key)
            end)
        end
        if d.product_item and not registered[d.product_item] then
            registered[d.product_item] = true
            local item = d.product_item
            inv.RegisterUsableItem(item, function(src)
                TriggerClientEvent('v-drugs:client:offer', src, item)
            end)
        end
    end
    -- The refined forms sell too, and they are the ones a dealer actually carries.
    for item in pairs(Config.ProductMult or {}) do
        if not registered[item] then
            registered[item] = true
            local it = item
            inv.RegisterUsableItem(it, function(src)
                TriggerClientEvent('v-drugs:client:offer', src, it)
            end)
        end
    end
end)

-- ── Exports ───────────────────────────────────────────────────
exports('GetHeat',   function(cid) return math.floor(heatOf(cid)) end)
exports('AddHeat',   function(cid, n) addHeat(cid, num(n)) end)
exports('GetPlants', function() return Plants end)
exports('GetDemand', function(district) return demandFor(tostring(district or '')) end)
