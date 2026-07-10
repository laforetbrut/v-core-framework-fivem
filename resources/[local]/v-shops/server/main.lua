-- v-shops | server
local Core = exports['v-core']:GetCore()

local Shops    = {}   -- id -> { id, label, type, job, items = [{item, price}] }
local ItemDefs = {}   -- name -> row

CreateThread(function()
    while GetResourceState('oxmysql') ~= 'started' do Wait(100) end
    for _, r in ipairs(MySQL.query.await('SELECT * FROM items') or {}) do ItemDefs[r.name] = r end
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
        cash = player.money.cash, bank = player.money.bank,
        inv = inventoryView(player),
    })
end)

Core.RegisterCallback('v-shops:buy', function(source, resolve, data)
    local shop = Shops[data.shopId]
    local player = Core.GetPlayer(source)
    if not shop or not player then resolve(false); return end

    local price = priceOf(shop, data.item)
    local amount = math.floor(tonumber(data.amount) or 0)
    local account = (data.account == 'bank') and 'bank' or 'cash'
    if not price or amount <= 0 then resolve(false); return end

    local total = price * amount
    if (player.money[account] or 0) < total then
        Core.Notify(source, LP(source, 'shop.nofunds'), 'error'); resolve({ error = 'funds' }); return
    end

    -- Reserve inventory space first, then charge (refund-free path).
    if not exports['v-inventory']:AddItem(source, data.item, amount) then
        Core.Notify(source, LP(source, 'shop.nospace'), 'error'); resolve({ error = 'space' }); return
    end
    player.RemoveMoney(account, total, 'shop-buy')

    Core.Log('shop', ('%s bought %dx %s for %d'):format(player.citizenid, amount, data.item, total), nil, player.citizenid)
    Core.Notify(source, LP(source, 'shop.bought', amount, ItemDefs[data.item].label, total), 'success')

    local p2 = Core.GetPlayer(source)   -- re-read for the post-purchase balances + inventory
    resolve({ cash = p2.money.cash, bank = p2.money.bank, inv = inventoryView(p2) })
end)
