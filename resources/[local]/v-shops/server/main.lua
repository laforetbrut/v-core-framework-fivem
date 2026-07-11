-- v-shops | server
local Core = exports['v-core']:GetCore()

local Shops    = {}   -- id -> { id, label, type, job, items = [{item, price}] }
local ItemDefs = {}   -- name -> row

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
end)

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
    for _, loc in ipairs(Config.Locations or {}) do
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
    local limits = exports['v-inventory']:GetLimits() or { maxSlots = 40, hotbar = 5 }
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

    -- Take the items first (authoritative count check), then pay.
    if (exports['v-inventory']:GetItemCount(source, data.item) or 0) < amount then
        resolve({ error = 'count' }); return
    end
    if not exports['v-inventory']:RemoveItem(source, data.item, amount) then resolve({ error = 'count' }); return end

    local total = price * amount
    local payout = (Config.SellPayout and Config.SellPayout[shop.id]) or 'cash'
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
    -- so the player can never keep goods they didn't pay for.
    if not player.RemoveMoney(account, total, 'shop-buy') then
        exports['v-inventory']:RemoveItem(source, data.item, amount)
        Core.Notify(source, LP(source, 'shop.nofunds'), 'error'); resolve({ error = 'funds' }); return
    end

    Core.Log('shop', ('%s bought %dx %s for %d'):format(player.citizenid, amount, data.item, total), nil, player.citizenid)
    Core.Notify(source, LP(source, 'shop.bought', amount, ItemDefs[data.item].label, total), 'success')

    local p2 = Core.GetPlayer(source)   -- re-read for the post-purchase balances + inventory
    resolve({ cash = p2.money.cash, bank = p2.money.bank, inv = inventoryView(p2) })
end)
