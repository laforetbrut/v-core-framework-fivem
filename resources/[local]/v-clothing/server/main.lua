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

-- ════════════════════════════════════════════════════════════════
--  Thumbnail generation (admin scan) + catalogue thumbnail serving
-- ════════════════════════════════════════════════════════════════
local ThumbDir   = Config.Thumbs.dir
local ThumbIndex = {}        -- cat -> { [drawableStr] = true }
local scanners   = {}        -- src -> true while allowed to write thumbs
local ResName    = GetCurrentResourceName()

local function indexPath()        return ThumbDir .. '/index.json' end
local function thumbFile(cat, d)  return ('%s/%s_%d.txt'):format(ThumbDir, cat, d) end

local function loadIndex()
    local raw = LoadResourceFile(ResName, indexPath())
    if raw and raw ~= '' then
        local ok, t = pcall(json.decode, raw)
        if ok and type(t) == 'table' then ThumbIndex = t end
    end
end
local function saveIndex()
    SaveResourceFile(ResName, indexPath(), json.encode(ThumbIndex), -1)
end
CreateThread(loadIndex)

-- Receive one captured thumbnail from the scanning admin. Guarded: only a
-- source currently flagged as a scanner (issued /scanclothes) may write.
RegisterNetEvent('v-clothing:server:saveThumb', function(cat, drawable, dataUri)
    local src = source
    if not scanners[src] then return end
    if type(cat) ~= 'string' or type(dataUri) ~= 'string' then return end
    if not catByKey(cat) then return end
    if #dataUri > Config.Thumbs.maxBytes then return end
    drawable = math.floor(tonumber(drawable) or -1)
    if drawable < 0 then return end
    SaveResourceFile(ResName, thumbFile(cat, drawable), dataUri, -1)
    ThumbIndex[cat] = ThumbIndex[cat] or {}
    ThumbIndex[cat][tostring(drawable)] = true
end)

RegisterNetEvent('v-clothing:server:scanProgress', function(done, total)
    local src = source
    if not scanners[src] then return end
    Core.Notify(src, LP(src, 'cl.scan_prog', tostring(done), tostring(total)), 'info')
end)

RegisterNetEvent('v-clothing:server:scanDone', function(count)
    local src = source
    if not scanners[src] then return end
    scanners[src] = nil
    saveIndex()
    local player = Core.GetPlayer(src)
    Core.Notify(src, LP(src, 'cl.scan_done', tostring(count or 0)), 'success')
    Core.Log('clothing', 'scan complete', { count = count }, player and player.citizenid or '')
end)

-- Catalogue: which drawables of a category already have a thumbnail.
Core.RegisterCallback('v-clothing:thumbIndex', function(source, resolve, cat)
    local set, list = ThumbIndex[cat] or {}, {}
    for k in pairs(set) do list[#list + 1] = tonumber(k) end
    resolve(list)
end)

-- Catalogue: fetch one thumbnail (base64 data URI) on demand.
Core.RegisterCallback('v-clothing:thumb', function(source, resolve, data)
    local cat = data and data.category
    local d   = math.floor(tonumber(data and data.drawable) or -1)
    if not cat or d < 0 or not (ThumbIndex[cat] and ThumbIndex[cat][tostring(d)]) then resolve(false); return end
    local raw = LoadResourceFile(ResName, thumbFile(cat, d))
    resolve((raw and raw ~= '') and raw or false)
end)

-- Admin command: (re)generate thumbnails.  /scanclothes            → all
--   /scanclothes new            → only missing (newly-added clothing)
--   /scanclothes <category>     → a single category (masks, tops, …)
RegisterCommand('scanclothes', function(src, args)
    if src == 0 then print('[v-clothing] /scanclothes must be run in-game'); return end
    local player = Core.GetPlayer(src)
    if not player or not player.HasPermission(Config.Thumbs.permission) then
        Core.Notify(src, LP(src, 'cl.noperm'), 'error'); return
    end
    if scanners[src] then Core.Notify(src, LP(src, 'cl.scan_busy'), 'error'); return end
    local a1 = (args[1] or ''):lower()
    local mode, onlyCat = 'all', nil
    if a1 == 'new' then mode = 'new'
    elseif a1 ~= '' and a1 ~= 'all' and catByKey(a1) then onlyCat = a1 end
    scanners[src] = true
    -- safety: auto-clear the scanner flag if the client never reports back
    SetTimeout(600000, function() scanners[src] = nil end)
    Core.Log('clothing', 'scan start', { mode = mode, cat = onlyCat }, player.citizenid)
    Core.Notify(src, LP(src, 'cl.scan_start', onlyCat or mode), 'info')
    TriggerClientEvent('v-clothing:client:startScan', src, mode, onlyCat)
end, false)

AddEventHandler('playerDropped', function() scanners[source] = nil end)

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
