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

Core.RegisterCallback('v-shops:getShop', function(source, resolve, shopId)
    local shop = Shops[shopId]
    local player = Core.GetPlayer(source)
    if not shop or not player then resolve(false); return end
    local list = {}
    for _, e in ipairs(shop.items) do
        local d = ItemDefs[e.item]
        if d then
            list[#list + 1] = { name = d.name, label = d.label, price = e.price, weight = d.weight, category = d.category }
        end
    end
    resolve({ id = shop.id, label = shop.label, items = list, cash = player.money.cash, bank = player.money.bank })
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

    local p2 = Core.GetPlayer(source)   -- re-read for the post-purchase balances
    resolve({ cash = p2.money.cash, bank = p2.money.bank })
end)
