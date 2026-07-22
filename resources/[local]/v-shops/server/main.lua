-- v-shops | server
local Core = exports['v-core']:GetCore()

local Shops    = {}   -- id -> { id, label, type, job, items = [{item, price}] }
local ItemDefs = {}   -- name -> row

-- Live store locations. Sourced from the DB via v-world (admin-editable in-game);
-- falls back to Config.Locations when v-world is absent, so a fresh install behaves
-- exactly as before. Shape stays { shop, coords = vector4, ped, noPed, noBlip }.
local Locations = Config.Locations

local function rebuildLocations()
    if GetResourceState('v-world') ~= 'started' then Locations = Config.Locations; return end
    local ok, rows = pcall(function() return exports['v-world']:GetShopLocations() end)
    if not ok or type(rows) ~= 'table' or #rows == 0 then Locations = Config.Locations; return end
    local out = {}
    for _, r in ipairs(rows) do
        if r.enabled == 1 or r.enabled == true then
            out[#out + 1] = {
                shop   = r.shop,
                coords = vector4(r.x + 0.0, r.y + 0.0, r.z + 0.0, (r.h or 0.0) + 0.0),
                ped    = r.ped,
                noPed  = (r.ped == nil or r.ped == ''),
                noBlip = not (r.blip == 1 or r.blip == true),
            }
        end
    end
    Locations = out
end

-- Client-facing shape (vector4 doesn't survive the net boundary cleanly).
local function locationPayload()
    local out = {}
    for _, l in ipairs(Locations) do
        out[#out + 1] = { shop = l.shop, x = l.coords.x, y = l.coords.y, z = l.coords.z, w = l.coords.w,
                          ped = l.ped, noPed = l.noPed == true, noBlip = l.noBlip == true }
    end
    return out
end

local function pushLocations(target)
    TriggerClientEvent('v-shops:client:locations', target or -1, locationPayload())
end

exports('GetLocations', function() return Locations end)

CreateThread(function()
    while GetResourceState('oxmysql') ~= 'started' do Wait(100) end
    for _, r in ipairs(MySQL.query.await('SELECT * FROM items') or {}) do ItemDefs[r.name] = r end
    -- Seed any missing default shops (e.g. the sell-only scrap dealer).
    for _, s in ipairs(Config.SeedShops or {}) do
        MySQL.insert.await('INSERT IGNORE INTO shops (id, label, type, items) VALUES (?,?,?,?)',
            { s.id, s.label, s.type or 'general', s.items or '[]' })
    end
    for _, s in ipairs(MySQL.query.await('SELECT * FROM shops') or {}) do
        Shops[s.id] = {
            id = s.id, label = s.label, type = s.type, job = s.job,
            items = (type(s.items) == 'table') and s.items or (json.decode(s.items or '[]') or {}),
        }
    end

    -- Hand our static locations to v-world once (it only seeds when its table is
    -- empty), then follow the DB from there so admins can move/add stores in-game.
    if GetResourceState('v-world') ~= 'missing' then
        local t = 0
        while GetResourceState('v-world') ~= 'started' and t < 100 do Wait(100); t = t + 1 end
        if GetResourceState('v-world') == 'started' then
            t = 0
            while not (pcall(function() return exports['v-world']:IsReady() end) and exports['v-world']:IsReady()) and t < 100 do
                Wait(100); t = t + 1
            end
            local seed = {}
            for _, l in ipairs(Config.Locations or {}) do
                seed[#seed + 1] = { shop = l.shop, x = l.coords.x, y = l.coords.y, z = l.coords.z,
                                    h = l.coords.w, ped = (not l.noPed) and (l.ped or 'mp_m_shopkeep_01') or nil,
                                    blip = not l.noBlip }
            end
            pcall(function() exports['v-world']:SeedShopLocations(seed) end)
            rebuildLocations()
        end
    end
    pushLocations()
end)

-- An admin moved/added/removed a store in the panel -> apply live.
AddEventHandler('v-world:server:changed', function(domain)
    if domain == nil or domain == 'shops' then rebuildLocations(); pushLocations() end
end)

-- A client that just spawned asks for the current store list.
RegisterNetEvent('v-shops:server:requestLocations', function() pushLocations(source) end)

local function priceOf(shop, itemName)
    for _, e in ipairs(shop.items) do if e.item == itemName then return e.price end end
    return nil
end

-- Server-authoritative access check: the player must be standing at a physical store
-- that maps to this shop id, and must hold the shop's job if it is job-locked. Coords
-- live in the shared Config.Locations, so the server can validate them (the client
-- cannot be trusted to only send shops it is actually next to).
local function canUseShop(source, shop)
    local ped = GetPlayerPed(source)
    if not ped or ped == 0 then return false, 'too_far' end
    local pos = GetEntityCoords(ped)
    local near = false
    for _, loc in ipairs(Locations or {}) do
        if loc.shop == shop.id and #(pos - vector3(loc.coords.x, loc.coords.y, loc.coords.z)) <= (Config.Distance + 3.0) then
            near = true; break
        end
    end
    if not near then return false, 'too_far' end
    if shop.job and shop.job ~= '' then
        local player = Core.GetPlayer(source)
        local job = player and player.job
        if not job or job.name ~= shop.job then return false, 'no_job' end
    end
    return true
end

-- Compact item def (label/image/weight/category/rarity) for the NUI, keyed by name.
local function defOf(name)
    local d = ItemDefs[name]
    if not d then return nil end
    local meta = d.metadata
    if type(meta) == 'string' then meta = json.decode(meta) or {} end
    return { label = d.label, image = d.image, weight = d.weight, category = d.category, rarity = (meta and meta.rarity) or 'common' }
end

-- The player's inventory as a view for the shop panel: items + the defs they need.
local function inventoryView(player)
    local items = exports['v-inventory']:GetItems(player.source) or {}
    local limits = exports['v-inventory']:GetLimits(player.source) or { maxSlots = 40, hotbar = 5 }
    local defs = {}
    for _, it in ipairs(items) do defs[it.name] = defs[it.name] or defOf(it.name) end
    return { items = items, defs = defs, maxSlots = limits.maxSlots or 40, hotbar = limits.hotbar or 5 }
end

Core.RegisterCallback('v-shops:getShop', function(source, resolve, shopId)
    local shop = Shops[shopId]
    local player = Core.GetPlayer(source)
    if not shop or not player then resolve(false); return end
    local ok = canUseShop(source, shop)
    if not ok then resolve(false); return end
    local list = {}
    for _, e in ipairs(shop.items) do
        local d = ItemDefs[e.item]
        if d then
            local meta = d.metadata
            if type(meta) == 'string' then meta = json.decode(meta) or {} end
            list[#list + 1] = { name = d.name, label = d.label, price = e.price, weight = d.weight,
                category = d.category, image = d.image, rarity = (meta and meta.rarity) or 'common' }
        end
    end
    resolve({
        id = shop.id, label = shop.label, items = list,
        sell = Config.SellLists[shop.id] or {},
        rate = (Config.SellRate and Config.SellRate[shop.id]) or 1,
        cash = player.money.cash, bank = player.money.bank,
        inv = inventoryView(player),
    })
end)

Core.RegisterCallback('v-shops:sell', function(source, resolve, data)
    local shop = Shops[data.shopId]
    local player = Core.GetPlayer(source)
    if not shop or not player then resolve(false); return end

    local ok, why = canUseShop(source, shop)
    if not ok then
        Core.Notify(source, LP(source, why == 'no_job' and 'shop.no_job' or 'shop.too_far'), 'error')
        resolve({ error = why }); return
    end

    local price = (Config.SellLists[shop.id] or {})[data.item]
    local amount = math.floor(tonumber(data.amount) or 0)
    if not price or amount <= 0 then resolve(false); return end
    amount = math.min(amount, 1000)

    -- Compute the payout BEFORE taking anything, so a sale that floors to $0
    -- (e.g. 1 marked bill at a 0.65 launderer) can never destroy the goods.
    local rate = (Config.SellRate and Config.SellRate[shop.id]) or 1
    local total = math.floor(price * amount * rate)
    local payout = (Config.SellPayout and Config.SellPayout[shop.id]) or 'cash'
    if total <= 0 then
        Core.Notify(source, LP(source, 'shop.too_small'), 'error'); resolve({ error = 'amount' }); return
    end

    -- Verify ownership, then take the items, then pay.
    if (exports['v-inventory']:GetItemCount(source, data.item) or 0) < amount then
        resolve({ error = 'count' }); return
    end
    if not exports['v-inventory']:RemoveItem(source, data.item, amount) then resolve({ error = 'count' }); return end

    if payout == 'dirty' then
        -- Pay in marked_bills (1 per $). If the payout can't fit, refund the goods.
        if not exports['v-inventory']:AddItem(source, 'marked_bills', total) then
            exports['v-inventory']:AddItem(source, data.item, amount)
            Core.Notify(source, LP(source, 'shop.nospace'), 'error'); resolve({ error = 'space' }); return
        end
    else
        player.AddMoney('cash', total, 'shop-sell')
    end

    Core.Log('shop', ('%s sold %dx %s for %d (%s)'):format(player.citizenid, amount, data.item, total, payout), nil, player.citizenid)
    Core.Notify(source, LP(source, payout == 'dirty' and 'shop.sold_dirty' or 'shop.sold', amount, (ItemDefs[data.item] and ItemDefs[data.item].label) or data.item, total), 'success')

    local p2 = Core.GetPlayer(source)
    resolve({ cash = p2.money.cash, bank = p2.money.bank, inv = inventoryView(p2), sold = true })
end)

Core.RegisterCallback('v-shops:buy', function(source, resolve, data)
    local shop = Shops[data.shopId]
    local player = Core.GetPlayer(source)
    if not shop or not player then resolve(false); return end

    local ok, why = canUseShop(source, shop)
    if not ok then
        Core.Notify(source, LP(source, why == 'no_job' and 'shop.no_job' or 'shop.too_far'), 'error')
        resolve({ error = why }); return
    end

    local price = priceOf(shop, data.item)
    local amount = math.floor(tonumber(data.amount) or 0)
    local account = (data.account == 'bank') and 'bank' or 'cash'
    if not price or amount <= 0 then resolve(false); return end
    amount = math.min(amount, 100)   -- server-side clamp (client stepper caps at 99)
    if not ItemDefs[data.item] then resolve(false); return end   -- guard the label index below

    local total = price * amount
    if (player.money[account] or 0) < total then
        Core.Notify(source, LP(source, 'shop.nofunds'), 'error'); resolve({ error = 'funds' }); return
    end

    -- Reserve inventory space first, then charge (refund-free path).
    -- data.slot: the inventory cell the player dropped on (drag-to-buy); nil = auto.
    if not exports['v-inventory']:AddItem(source, data.item, amount, nil, tonumber(data.slot)) then
        Core.Notify(source, LP(source, 'shop.nospace'), 'error'); resolve({ error = 'space' }); return
    end
    -- Charge only after the item is granted; if the charge fails (race), refund the item
    -- so the player can never keep goods they didn't pay for. total==0 (a free item) is
    -- allowed through without a charge (RemoveMoney rejects a 0 amount).
    if total > 0 and not player.RemoveMoney(account, total, 'shop-buy') then
        exports['v-inventory']:RemoveItem(source, data.item, amount)
        Core.Notify(source, LP(source, 'shop.nofunds'), 'error'); resolve({ error = 'funds' }); return
    end

    Core.Log('shop', ('%s bought %dx %s for %d'):format(player.citizenid, amount, data.item, total), nil, player.citizenid)
    Core.Notify(source, LP(source, 'shop.bought', amount, ItemDefs[data.item].label, total), 'success')

    local p2 = Core.GetPlayer(source)   -- re-read for the post-purchase balances + inventory
    resolve({ cash = p2.money.cash, bank = p2.money.bank, inv = inventoryView(p2) })
end)
