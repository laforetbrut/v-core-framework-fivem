-- v-fuel | server
-- Prices, charges and the authoritative fuel write. The client runs the pump animation
-- and reports how much it drew; the server re-derives the price from ITS OWN station and
-- type tables, clamps the litres to what the tank could physically take, and only then
-- charges. A patched client can ask for 9999 litres — it will be billed for the tank.
local Core = exports['v-core']:GetCore()

local Stations = Config.Stations   -- runtime list (DB, or config fallback)
local Sessions = {}                -- src -> { station, type, plate, netid, start }

local function rebuildStations()
    local rows = (GetResourceState('v-world') == 'started' and exports['v-world']:IsReady())
        and exports['v-world']:GetStations() or nil
    local list = {}
    for _, r in ipairs(rows or {}) do
        if r.enabled == 1 then list[#list + 1] = r end
    end
    if #list == 0 then list = Config.Stations end
    Stations = list
    TriggerClientEvent('v-fuel:client:stations', -1, Stations)
end

local function stationById(id)
    for _, st in ipairs(Stations) do if st.id == id then return st end end
end

local function stationSells(st, fuelType)
    for k in tostring(st.types or ''):gmatch('[^,%s]+') do
        if k == fuelType then return true end
    end
    return false
end

--- Unit price at a station, after its multiplier. Rounded to the cent so the UI and the
--- charge can never disagree by a rounding step.
local function unitPrice(st, fuelType)
    local t = Config.Types[fuelType]
    if not t then return nil end
    return math.floor(t.price * (tonumber(st.mult) or 1.0) * 100 + 0.5) / 100
end

-- ── Open a pump ────────────────────────────────────────────────
Core.RegisterCallback('v-fuel:open', function(source, resolve, data)
    local st = stationById(type(data) == 'table' and tostring(data.station or '') or '')
    if not st then resolve(false); return end
    local p = Core.GetPlayer(source)
    if not p then resolve(false); return end

    local ped = GetPlayerPed(source)
    if not ped or ped == 0 then resolve({ error = 'far' }); return end
    if #(GetEntityCoords(ped) - vector3(st.x + 0.0, st.y + 0.0, st.z + 0.0)) > (Config.Distance + 4.0) then
        resolve({ error = 'far' }); return
    end

    local types = {}
    for k in tostring(st.types or ''):gmatch('[^,%s]+') do
        local t = Config.Types[k]
        if t then
            types[#types + 1] = { key = k, i18n = t.i18n, price = unitPrice(st, k),
                                  color = t.color, octane = t.octane }
        end
    end
    resolve({
        station = { id = st.id, label = st.label },
        types = types, cash = p.money.cash, bank = p.money.bank,
        vehicle = type(data) == 'table' and data.vehicle or nil,   -- purely informational
        jerry = Config.JerryCan.item,
        jerryCap = Config.JerryCan.capacity,
    })
end)

-- ── Refuel ─────────────────────────────────────────────────────
-- `litres` is what the client says it drew, `tank` the tank size it computed. Both are
-- re-clamped here: litres to [0, tank], tank to the class table, so neither can inflate
-- the bill or the fuel granted.
Core.RegisterCallback('v-fuel:refuel', function(source, resolve, data)
    if type(data) ~= 'table' then resolve(false); return end
    local st = stationById(tostring(data.station or ''))
    local fuelType = tostring(data.type or '')
    local p = Core.GetPlayer(source)
    if not st or not p or not Config.Types[fuelType] then resolve(false); return end
    if not stationSells(st, fuelType) then resolve({ error = 'notsold' }); return end

    local ped = GetPlayerPed(source)
    if not ped or ped == 0 then resolve({ error = 'far' }); return end
    if #(GetEntityCoords(ped) - vector3(st.x + 0.0, st.y + 0.0, st.z + 0.0)) > (Config.Distance + 5.0) then
        resolve({ error = 'far' }); return
    end

    -- The vehicle must exist and be at the pump: re-read the entity, never the claim.
    local ent = tonumber(data.netid) and NetworkGetEntityFromNetworkId(tonumber(data.netid)) or 0
    if not ent or ent == 0 or not DoesEntityExist(ent) then resolve({ error = 'novehicle' }); return end
    if #(GetEntityCoords(ent) - vector3(st.x + 0.0, st.y + 0.0, st.z + 0.0)) > Config.NozzleRange + 2.0 then
        resolve({ error = 'novehicle' }); return
    end

    local tank = math.max(1, math.min(400, math.floor(tonumber(data.tank) or Config.DefaultTank)))
    local litres = math.max(0, math.min(tank, tonumber(data.litres) or 0))
    litres = math.floor(litres * 10 + 0.5) / 10
    if litres <= 0 then resolve({ error = 'nothing' }); return end

    local unit = unitPrice(st, fuelType)
    local total = math.ceil(litres * unit)
    local account = (data.account == 'bank') and 'bank' or 'cash'
    if (p.money[account] or 0) < total then
        Core.Notify(source, LP(source, 'fuel.nofunds'), 'error'); resolve({ error = 'funds' }); return
    end
    if not p.RemoveMoney(account, total, 'fuel-' .. fuelType) then
        resolve({ error = 'funds' }); return
    end

    -- Wrong fuel: charged (you pumped it), but it damages the engine instead of filling.
    local wrongFuel = data.wrongFuel and true or false
    if wrongFuel then
        Core.Log('fuel', ('%s put %s in the wrong tank at %s'):format(p.citizenid, fuelType, st.id), nil, p.citizenid)
        Core.Notify(source, LP(source, 'fuel.wrong'), 'error')
        TriggerClientEvent('v-fuel:client:wrongFuel', source, data.netid, Config.WrongFuel.engineDamage)
        local p2 = Core.GetPlayer(source)
        resolve({ ok = true, wrong = true, spent = total, cash = p2.money.cash, bank = p2.money.bank })
        return
    end

    Core.Log('fuel', ('%s bought %.1fL of %s for %d at %s'):format(p.citizenid, litres, fuelType, total, st.id),
        nil, p.citizenid)
    Core.Notify(source, LP(source, 'fuel.bought', string.format('%.1f', litres), total), 'success')
    local p2 = Core.GetPlayer(source)
    resolve({ ok = true, litres = litres, spent = total, cash = p2.money.cash, bank = p2.money.bank })
end)

-- ── Fill a jerry can ───────────────────────────────────────────
Core.RegisterCallback('v-fuel:fillCan', function(source, resolve, data)
    local st = stationById(type(data) == 'table' and tostring(data.station or '') or '')
    local p = Core.GetPlayer(source)
    if not st or not p then resolve(false); return end
    local ped = GetPlayerPed(source)
    if not ped or ped == 0 or
       #(GetEntityCoords(ped) - vector3(st.x + 0.0, st.y + 0.0, st.z + 0.0)) > (Config.Distance + 4.0) then
        resolve({ error = 'far' }); return
    end
    if not stationSells(st, Config.JerryCan.type) then resolve({ error = 'notsold' }); return end

    local cost = math.ceil(Config.JerryCan.capacity * Config.JerryCan.fillCost * (tonumber(st.mult) or 1.0))
    if not p.RemoveMoney('cash', cost, 'fuel-jerrycan') then
        Core.Notify(source, LP(source, 'fuel.nofunds'), 'error'); resolve({ error = 'funds' }); return
    end
    if not exports['v-inventory']:AddItem(source, Config.JerryCan.item, 1,
            { fuel = Config.JerryCan.capacity, type = Config.JerryCan.type }) then
        p.AddMoney('cash', cost, 'fuel-jerrycan-refund')   -- a failed grant must never keep the charge
        resolve({ error = 'space' }); return
    end
    Core.Notify(source, LP(source, 'fuel.can_filled', cost), 'success')
    local p2 = Core.GetPlayer(source)
    resolve({ ok = true, spent = cost, cash = p2.money.cash, bank = p2.money.bank })
end)

-- ── Boot / live reload ─────────────────────────────────────────
CreateThread(function()
    while GetResourceState('oxmysql') ~= 'started' do Wait(100) end
    -- the jerry can is an item like any other
    MySQL.insert.await(
        'INSERT IGNORE INTO items (name, label, weight, stackable, usable, category) VALUES (?,?,?,0,1,?)',
        { Config.JerryCan.item, 'Jerry Can', 4000, 'tools' })

    local tries = 0
    while GetResourceState('v-world') == 'started' and not exports['v-world']:IsReady() and tries < 100 do
        Wait(100); tries = tries + 1
    end
    if GetResourceState('v-world') == 'started' and exports['v-world']:IsReady() then
        exports['v-world']:SeedStations(Config.Stations)
    end
    rebuildStations()
end)

AddEventHandler('v-world:server:changed', function(domain)
    if domain == nil or domain == 'stations' then rebuildStations() end
end)

RegisterNetEvent('v-fuel:server:request', function()
    TriggerClientEvent('v-fuel:client:stations', source, Stations)
end)

AddEventHandler('playerDropped', function() Sessions[source] = nil end)

exports('GetStations', function() return Stations end)
exports('GetTypes', function() return Config.Types end)
