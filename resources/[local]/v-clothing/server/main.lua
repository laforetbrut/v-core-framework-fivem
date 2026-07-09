-- v-clothing | server
local Core = exports['v-core']:GetCore()

local Cats = {}   -- item name -> category def
for _, c in ipairs(Config.Categories) do Cats[c.item] = c end

local function catByKey(key)
    for _, c in ipairs(Config.Categories) do if c.key == key then return c end end
end

-- Ensure the clothing item definitions exist (managed like any other item).
CreateThread(function()
    while GetResourceState('oxmysql') ~= 'started' do Wait(100) end
    for _, c in ipairs(Config.Categories) do
        MySQL.insert.await(
            'INSERT IGNORE INTO items (name, label, weight, stackable, usable, category) VALUES (?, ?, ?, 0, 1, ?)',
            { c.item, c.item:sub(1, 1):upper() .. c.item:sub(2), 200, 'clothing' })
    end
end)

local function worn(player)
    local w = player.GetMetadata('worn')
    return (type(w) == 'table') and w or {}
end

-- ── Buy: create a clothing item from the current preview ───────
Core.RegisterCallback('v-clothing:buy', function(source, resolve, data)
    local player = Core.GetPlayer(source)
    local cat = catByKey(data.category)
    if not player or not cat then resolve(false); return end
    if (player.money.cash or 0) < cat.price then
        Core.Notify(source, LP(source, 'cl.nofunds'), 'error'); resolve({ error = 'funds' }); return
    end
    local meta = { cat = cat.key, kind = cat.kind, id = cat.id, drawable = data.drawable or 0, texture = data.texture or 0 }
    if not exports['v-inventory']:AddItem(source, cat.item, 1, meta) then
        resolve({ error = 'space' }); return
    end
    player.RemoveMoney('cash', cat.price, 'clothing-buy')
    Core.Log('clothing', ('%s bought %s'):format(player.citizenid, cat.item), meta, player.citizenid)
    Core.Notify(source, LP(source, 'cl.bought', LP(source, 'item.' .. cat.item), cat.price), 'success')
    local p2 = Core.GetPlayer(source)
    resolve({ cash = p2.money.cash, bank = p2.money.bank })
end)

-- ── Equip (clothing item "used" via the inventory) ─────────────
local function equip(source, item)
    local player = Core.GetPlayer(source)
    if not player or not item or not item.metadata then return end
    local m = item.metadata
    local cat = m.cat
    local w = worn(player)
    -- return the currently worn piece of this category to the inventory first
    if w[cat] then
        exports['v-inventory']:AddItem(source, w[cat].item, 1, w[cat].meta)
    end
    w[cat] = { item = item.name, meta = m }
    player.SetMetadata('worn', w)
    TriggerClientEvent('v-clothing:client:apply', source, m)   -- apply on the ped + persist appearance
    Core.Notify(source, LP(source, 'cl.equipped', LP(source, 'item.' .. item.name)), 'success')
end

for _, c in ipairs(Config.Categories) do
    exports['v-inventory']:RegisterUsableItem(c.item, function(src, item) equip(src, item) end)
end

-- ── Wardrobe: list worn + unequip ──────────────────────────────
Core.RegisterCallback('v-clothing:getWorn', function(source, resolve)
    local player = Core.GetPlayer(source)
    if not player then resolve(false); return end
    local list = {}
    for cat, entry in pairs(worn(player)) do
        list[#list + 1] = { cat = cat, item = entry.item, drawable = entry.meta.drawable, texture = entry.meta.texture }
    end
    resolve(list)
end)

Core.RegisterCallback('v-clothing:unequip', function(source, resolve, catKey)
    local player = Core.GetPlayer(source)
    local cat = catByKey(catKey)
    if not player or not cat then resolve(false); return end
    local w = worn(player)
    local entry = w[catKey]
    if not entry then resolve(false); return end
    exports['v-inventory']:AddItem(source, entry.item, 1, entry.meta)   -- give the piece back
    w[catKey] = nil
    player.SetMetadata('worn', w)
    -- revert to the bare default for this slot
    local m = { cat = cat.key, kind = cat.kind, id = cat.id, drawable = Config.NudeDefaults[cat.id] or 0, texture = 0, off = (cat.kind == 'prop') }
    TriggerClientEvent('v-clothing:client:apply', source, m)
    Core.Notify(source, LP(source, 'cl.unequipped', LP(source, 'item.' .. entry.item)), 'info')
    -- return the updated worn list
    local list = {}
    for c, e in pairs(worn(player)) do list[#list + 1] = { cat = c, item = e.item, drawable = e.meta.drawable, texture = e.meta.texture } end
    resolve(list)
end)
