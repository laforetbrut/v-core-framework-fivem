
-- Consumers ask for the capability, not the resource: a server that replaces this
-- module keeps every consumer working.
V.Provide('clothing')
-- v-clothing | server
local Core = exports['v-core']:GetCore()

-- The wearable categories live in `clothing_categories` (owned by v-world) and are
-- editable from the admin panel. Config.Categories is first-boot seed data only.
local Categories = Config.Categories       -- runtime list
local Cats = {}                            -- item name -> category def
local registered = {}                      -- item -> usable handler already bound
local equip                                -- forward declaration (defined below, used by rebuild)

local function catByKey(key)
    for _, c in ipairs(Categories) do if c.key == key then return c end end
end
local function catByItem(item) return Cats[item] end

-- Categories that share this one's ped slot. GTA renders a single drawable per
-- component/prop id, so equipping gloves must evict bare arms and vice-versa.
local function sameSlot(cat)
    local out = {}
    for _, c in ipairs(Categories) do
        if c.key ~= cat.key and c.kind == cat.kind and c.id == cat.id then out[#out + 1] = c.key end
    end
    return out
end

local function rebuildCategories()
    local rows = (GetResourceState('v-world') == 'started' and exports['v-world']:IsReady())
        and exports['v-world']:GetClothCategories() or nil
    local list = {}
    if rows and #rows > 0 then
        for _, r in ipairs(rows) do
            if r.enabled == 1 then
                list[#list + 1] = {
                    key = r.key, i18n = 'cl.' .. r.key, label = r.label,
                    kind = (r.kind == 'prop') and 'prop' or 'comp',
                    id = math.floor(tonumber(r.slot) or 0),
                    price = math.floor(tonumber(r.price) or 0),
                    item = r.item, framing = r.framing or Config.DefaultFraming,
                }
            end
        end
    end
    if #list == 0 then list = Config.Categories end   -- never leave the store empty
    Categories = list

    Cats = {}
    for _, c in ipairs(Categories) do Cats[c.item] = c end

    for _, c in ipairs(Categories) do
        -- every category mints an inventory item; make sure the definition exists
        MySQL.insert.await(
            'INSERT IGNORE INTO items (name, label, weight, stackable, usable, category) VALUES (?, ?, ?, 0, 1, ?)',
            { c.item, c.label or (c.item:sub(1, 1):upper() .. c.item:sub(2)), 200, 'clothing' })
        if not registered[c.item] then
            registered[c.item] = true
            exports['v-inventory']:RegisterUsableItem(c.item, function(src, item) equip(src, item) end)
        end
    end
    TriggerClientEvent('v-clothing:client:categories', -1, Categories)
end

exports('GetCategories', function() return Categories end)

CreateThread(function()
    while GetResourceState('oxmysql') ~= 'started' do Wait(100) end
    -- wait for v-world, then seed this module's defaults into it once
    local tries = 0
    while GetResourceState('v-world') == 'started' and not exports['v-world']:IsReady() and tries < 100 do
        Wait(100); tries = tries + 1
    end
    if GetResourceState('v-world') == 'started' and exports['v-world']:IsReady() then
        exports['v-world']:SeedClothCategories(Config.Categories)
        local locs = {}
        for _, l in ipairs(Config.Locations) do
            locs[#locs + 1] = { label = l.label, x = l.coords.x, y = l.coords.y, z = l.coords.z,
                                h = l.coords.w, ped = Config.PedModel }
        end
        exports['v-world']:SeedClothStores(locs)
    end
    rebuildCategories()
end)

-- ── Store locations (DB-backed, pushed live) ───────────────────
local function storePayload()
    local rows = (GetResourceState('v-world') == 'started' and exports['v-world']:IsReady())
        and exports['v-world']:GetClothStores() or nil
    local out = {}
    for _, r in ipairs(rows or {}) do
        if r.enabled == 1 then
            out[#out + 1] = { id = r.id, label = r.label, x = r.x, y = r.y, z = r.z, h = r.h,
                              ped = r.ped, blip = r.blip, job = r.job }
        end
    end
    if #out == 0 then
        for i, l in ipairs(Config.Locations) do
            out[#out + 1] = { id = -i, label = l.label, x = l.coords.x, y = l.coords.y,
                              z = l.coords.z, h = l.coords.w, ped = Config.PedModel, blip = 1 }
        end
    end
    return out
end

local function pushStores(target)
    TriggerClientEvent('v-clothing:client:stores', target or -1, storePayload())
end

RegisterNetEvent('v-clothing:server:request', function()
    TriggerClientEvent('v-clothing:client:categories', source, Categories)
    pushStores(source)
end)

AddEventHandler('v-world:server:changed', function(domain)
    if domain == nil or domain == 'clothcats' then rebuildCategories() end
    if domain == nil or domain == 'clothstores' then pushStores() end
end)

-- Is `src` physically at a clothing store they are allowed to use?
local function atStore(src)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return false end
    local c = GetEntityCoords(ped)
    for _, l in ipairs(storePayload()) do
        if #(c - vector3(l.x + 0.0, l.y + 0.0, l.z + 0.0)) <= (Config.Distance + 2.5) then
            if l.job and l.job ~= '' then
                local p = Core.GetPlayer(src)
                local job = p and p.job          -- { name, grade }
                if not job or job.name ~= l.job then return false end
            end
            return true
        end
    end
    return false
end

local function worn(player)
    local w = player.GetMetadata('worn')
    return (type(w) == 'table') and w or {}
end

-- ── Buy: create a clothing item from the current preview ───────
Core.RegisterCallback('v-clothing:buy', function(source, resolve, data)
    local player = Core.GetPlayer(source)
    local cat = catByKey(data.category)
    if not player or not cat then resolve(false); return end
    if not atStore(source) then
        Core.Notify(source, LP(source, 'cl.toofar'), 'error'); resolve({ error = 'far' }); return
    end
    -- one derived price, used by the funds check, the charge and the notification
    local price = math.max(0, math.floor((cat.price or 0) * (Config.PriceMult or 1.0)))
    if (player.money.cash or 0) < price then
        Core.Notify(source, LP(source, 'cl.nofunds'), 'error'); resolve({ error = 'funds' }); return
    end
    -- Coerce + clamp the client-supplied drawable/texture so a malformed value can't
    -- reach math.floor() during apply and error out.
    local dr = math.floor(tonumber(data.drawable) or 0); if dr < 0 then dr = 0 end
    local tx = math.floor(tonumber(data.texture) or 0); if tx < 0 then tx = 0 end
    local meta = { cat = cat.key, kind = cat.kind, id = cat.id, drawable = dr, texture = tx }
    if not exports['v-inventory']:AddItem(source, cat.item, 1, meta) then
        resolve({ error = 'space' }); return
    end
    player.RemoveMoney('cash', price, 'clothing-buy')
    Core.Log('clothing', ('%s bought %s'):format(player.citizenid, cat.item), meta, player.citizenid)
    Core.Notify(source, LP(source, 'cl.bought', LP(source, 'item.' .. cat.item), price), 'success')
    local p2 = Core.GetPlayer(source)
    resolve({ cash = p2.money.cash, bank = p2.money.bank })
end)

-- ── Equip (clothing item "used" via the inventory) ─────────────
function equip(source, item)
    local player = Core.GetPlayer(source)
    if not player or not item or not item.metadata then return end
    local m = item.metadata
    local cat = m.cat
    local def = catByKey(cat) or catByItem(item.name)
    local w = worn(player)
    -- A ped renders one drawable per slot: return any garment sharing this slot first,
    -- otherwise it would stay "worn" in the data while being invisible on the ped.
    if def then
        for _, other in ipairs(sameSlot(def)) do
            if w[other] then
                if not exports['v-inventory']:AddItem(source, w[other].item, 1, w[other].meta) then
                    Core.Notify(source, LP(source, 'cl.nospace'), 'error'); return
                end
                w[other] = nil
            end
        end
    end
    -- return the currently worn piece of this category to the inventory first — abort
    -- the swap if it can't fit, so the worn piece isn't destroyed by a full inventory
    if w[cat] then
        if not exports['v-inventory']:AddItem(source, w[cat].item, 1, w[cat].meta) then
            Core.Notify(source, LP(source, 'cl.nospace'), 'error'); return
        end
    end
    w[cat] = { item = item.name, meta = m }
    player.SetMetadata('worn', w)
    TriggerClientEvent('v-clothing:client:apply', source, m)   -- apply on the ped + persist appearance
    Core.Notify(source, LP(source, 'cl.equipped', LP(source, 'item.' .. item.name)), 'success')
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
local scanners   = {}        -- src -> { token } while a scan is running
local tokenSrc   = {}        -- upload token -> src
local ResName    = GetCurrentResourceName()
local thumbCache, thumbCacheN = {}, 0   -- in-memory data-URI cache (disk saver)

math.randomseed(os.time())
local function newToken()
    local t = {}
    for i = 1, 32 do t[i] = string.format('%x', math.random(0, 15)) end
    return table.concat(t)
end

local function clearScanner(src)
    local sc = scanners[src]
    if sc and sc.token then tokenSrc[sc.token] = nil end
    scanners[src] = nil
end

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

-- Receive captured thumbnails over HTTP (NEVER over net events: large event
-- payloads trip FiveM's reliable-event overflow protection and KICK the
-- client). The NUI uploads each downscaled thumbnail to
-- http://<server>/v-clothing/upload with the one-shot scan token.
local savesSinceFlush = 0
SetHttpHandler(function(req, res)
    local cors = { ['Access-Control-Allow-Origin'] = '*' }
    if req.method ~= 'POST' or req.path ~= '/upload' then
        res.writeHead(404, cors); res.send('not found'); return
    end
    req.setDataHandler(function(body)
        local ok, data = pcall(json.decode, body or '')
        if not ok or type(data) ~= 'table' then res.writeHead(400, cors); res.send('bad json'); return end
        local src = data.t and tokenSrc[data.t]
        local cat = type(data.cat) == 'string' and catByKey(data.cat) or nil
        local d   = math.floor(tonumber(data.d) or -1)
        local uri = data.uri
        if not src or not scanners[src] or not cat or d < 0
            or type(uri) ~= 'string' or uri:sub(1, 11) ~= 'data:image/'
            or #uri > Config.Thumbs.maxBytes then
            res.writeHead(400, cors); res.send('rejected'); return
        end
        SaveResourceFile(ResName, thumbFile(cat.key, d), uri, -1)
        ThumbIndex[cat.key] = ThumbIndex[cat.key] or {}
        ThumbIndex[cat.key][tostring(d)] = true
        -- keep the cache fresh AND counted, so the 400-entry cap can actually bound it
        local ck = cat.key .. '_' .. d
        if thumbCache[ck] == nil then
            if thumbCacheN > 400 then thumbCache, thumbCacheN = {}, 0 end
            thumbCacheN = thumbCacheN + 1
        end
        thumbCache[ck] = uri
        savesSinceFlush = savesSinceFlush + 1
        if savesSinceFlush >= 25 then savesSinceFlush = 0; saveIndex() end
        res.writeHead(200, { ['Access-Control-Allow-Origin'] = '*', ['Content-Type'] = 'application/json' })
        res.send('{"ok":true}')
    end)
end)

RegisterNetEvent('v-clothing:server:scanProgress', function(done, total)
    local src = source
    if not scanners[src] then return end
    Core.Notify(src, LP(src, 'cl.scan_prog', tostring(done), tostring(total)), 'info')
end)

RegisterNetEvent('v-clothing:server:scanDone', function(count)
    local src = source
    if not scanners[src] then return end
    clearScanner(src)
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

-- Small in-memory cache so repeated catalogue browsing doesn't hit the disk.
local function getThumb(cat, d)
    if not (ThumbIndex[cat] and ThumbIndex[cat][tostring(d)]) then return false end
    local k = cat .. '_' .. d
    local v = thumbCache[k]
    if v ~= nil then return v end
    local raw = LoadResourceFile(ResName, thumbFile(cat, d))
    v = (raw and raw ~= '') and raw or false
    if thumbCacheN > 400 then thumbCache, thumbCacheN = {}, 0 end   -- crude cap: reset when full
    thumbCache[k] = v; thumbCacheN = thumbCacheN + 1
    return v
end

-- Catalogue: fetch one thumbnail (base64 data URI) on demand.
Core.RegisterCallback('v-clothing:thumb', function(source, resolve, data)
    local cat = data and data.category
    local d   = math.floor(tonumber(data and data.drawable) or -1)
    if type(cat) ~= 'string' or d < 0 then resolve(false); return end
    resolve(getThumb(cat, d))
end)

-- Catalogue: fetch a batch of thumbnails (one round-trip per viewport).
Core.RegisterCallback('v-clothing:thumbs', function(source, resolve, list)
    if type(list) ~= 'table' then resolve({}); return end
    local out = {}
    for i = 1, math.min(#list, 32) do
        local e = list[i]
        local cat = e and e.cat
        local d   = e and math.floor(tonumber(e.d) or -1) or -1
        if type(cat) == 'string' and d >= 0 then
            local uri = getThumb(cat, d)
            if uri then out[#out + 1] = { cat = cat, d = d, uri = uri } end
        end
    end
    resolve(out)
end)

-- Start a thumbnail scan for an admin. mode: 'all' | 'new'; onlyCat optional.
local function beginScan(src, mode, onlyCat)
    local player = Core.GetPlayer(src)
    if not player or not player.HasPermission(Config.Thumbs.permission) then
        Core.Notify(src, LP(src, 'cl.noperm'), 'error'); return
    end
    if scanners[src] then Core.Notify(src, LP(src, 'cl.scan_busy'), 'error'); return end
    local token = newToken()
    scanners[src] = { token = token }
    tokenSrc[token] = src
    -- safety: auto-clear the scanner flag if the client never reports back
    -- (isolation shoots every piece twice: a full scan can take ~15 min)
    SetTimeout(1800000, function()
        if scanners[src] and scanners[src].token == token then clearScanner(src) end
    end)
    Core.Log('clothing', 'scan start', { mode = mode, cat = onlyCat }, player.citizenid)
    Core.Notify(src, LP(src, 'cl.scan_start', onlyCat or mode), 'info')
    TriggerClientEvent('v-clothing:client:startScan', src, mode, onlyCat, token)
end

-- Keybind entry point (this server has no chat) — F9 twice in-game.
-- Started from the admin panel (v-admin → Tools → Clothing scan). `beginScan` re-checks
-- the permission server-side, so the event is safe to expose.
--   mode = 'new'  → only the missing thumbnails      mode = 'all' → the whole catalogue
--   cat           → restrict to a single category (masks, tops, …)
RegisterNetEvent('v-clothing:server:requestScan', function(mode, cat)
    local onlyCat = (type(cat) == 'string' and cat ~= '' and catByKey(cat)) and cat or nil
    beginScan(source, (mode == 'all') and 'all' or 'new', onlyCat)
end)

AddEventHandler('playerDropped', function() clearScanner(source) end)

local function doUnequip(source, catKey)
    local player = Core.GetPlayer(source)
    local cat = catByKey(catKey)
    if not player or not cat then return false end
    local w = worn(player)
    local entry = w[catKey]
    if not entry then return false end
    -- Only remove the worn piece once it's safely back in the inventory (a full
    -- inventory must not silently delete the clothing item).
    if not exports['v-inventory']:AddItem(source, entry.item, 1, entry.meta) then
        Core.Notify(source, LP(source, 'cl.nospace'), 'error'); return false
    end
    w[catKey] = nil
    player.SetMetadata('worn', w)
    -- revert to the bare default for this slot
    local m = { cat = cat.key, kind = cat.kind, id = cat.id, drawable = Config.NudeDefaults[cat.id] or 0, texture = 0, off = (cat.kind == 'prop') }
    TriggerClientEvent('v-clothing:client:apply', source, m)
    Core.Notify(source, LP(source, 'cl.unequipped', LP(source, 'item.' .. entry.item)), 'info')
    local list = {}
    for c, e in pairs(worn(player)) do list[#list + 1] = { cat = c, item = e.item, drawable = e.meta.drawable, texture = e.meta.texture } end
    return list
end

Core.RegisterCallback('v-clothing:unequip', function(source, resolve, catKey)
    resolve(doUnequip(source, catKey) or false)
end)

-- ── Exports for v-inventory's equipment panel ──────────────────
exports('Unequip', function(src, catKey) return doUnequip(src, catKey) and true or false end)
exports('GetWorn', function(src)
    local player = Core.GetPlayer(src)
    if not player then return {} end
    local out = {}
    for cat, entry in pairs(worn(player)) do
        out[cat] = { item = entry.item, drawable = entry.meta.drawable, texture = entry.meta.texture }
    end
    return out
end)

-- ══════════════════════════════════════════════════════════════════
--  Admin-tunable settings (v-core module registry)
-- ══════════════════════════════════════════════════════════════════
-- Declared to v-core, which stores the values and serves them to the admin panel.
-- Applied back onto Config so the existing code paths see an operator's change without
-- a restart. See DEVELOPERS.md.
local function declareSettings()
    Core.RegisterModule('v-clothing', {
        label = 'Clothing', category = 'gameplay',
        settings = {

            { key = 'distance', label = 'Store range (m)',   type = 'number', default = Config.Distance, min = 0.5, max = 10 },
            { key = 'priceMult',label = 'Price multiplier',  type = 'number', default = 1.0, min = 0.1, max = 10 },
        },
    })
end

local function S(key, fallback) return Core.GetSetting('v-clothing', key, fallback) end

local function applySettings()

    Config.Distance  = S('distance', Config.Distance)
    Config.PriceMult = S('priceMult', 1.0)
end

AddEventHandler('v-core:server:settingChanged', function(mod)
    if mod == 'v-clothing' then applySettings() end
end)

V.Ready(function()
    declareSettings()
    applySettings()
end)
