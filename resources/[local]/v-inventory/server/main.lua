-- v-inventory | server
-- Items live as an array: { name, amount, slot, metadata }.
-- 'player' container = the v-core player inventory (synced back for saving).
-- secondary containers (trunk / glovebox / gang stash / ground) live in `Stashes`.
local Core = exports['v-core']:GetCore()

local ItemDefs    = {}   -- name -> row
local Inv         = {}   -- [source] = items[]
local Pocket      = {}   -- [source] = items[]  (hidden compartment, stored in metadata)
local Stashes     = {}   -- [id]     = { items, maxWeight, maxSlots, persistent }
local OpenStash    = {}   -- [source] = stash id currently open ('search' = frisking a player)
local SearchTarget = {}   -- [searcher src] = target src (frisk/steal target)
local UsableItems  = {}   -- name -> handler(src, item)
local Equipped     = {}   -- [source] = { slot, name }  currently-drawn weapon
local dropCounter  = 0
local MONEY        = 'money'

-- Use effects by item type (hooks v-status). Registered per usable item.
local function status(src, key, delta) pcall(function() exports['v-status']:Add(src, key, delta) end) end
local UseByType = {
    food    = function(src) status(src, 'hunger', 30) end,
    drink   = function(src) status(src, 'thirst', 30) end,
    drug    = function(src) status(src, 'stress', -25) end,
    medical = function(src, item, def)
        pcall(function() exports['v-status']:SetBleed(src, 0) end)
        local heal = (def and (def.name == 'medikit' or def.name == 'firstaid')) and 60 or 25
        TriggerClientEvent('v-inventory:client:heal', src, heal)
    end,
}

-- ── Item catalogue: seed the DB (INSERT IGNORE) then load defs ──
CreateThread(function()
    while GetResourceState('oxmysql') ~= 'started' do Wait(100) end
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS stashes (
        id VARCHAR(64) NOT NULL PRIMARY KEY,
        items JSON NOT NULL,
        updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])

    for _, it in ipairs(InventoryItems or {}) do
        MySQL.insert.await(
            [[INSERT INTO items (name, label, weight, stackable, usable, category, image, metadata)
              VALUES (?,?,?,?,?,?,?,?)
              ON DUPLICATE KEY UPDATE label=VALUES(label), weight=VALUES(weight), stackable=VALUES(stackable),
                usable=VALUES(usable), category=VALUES(category), image=VALUES(image), metadata=VALUES(metadata)]],
            { it.name, it.label, it.weight, it.stackable, it.usable, it.category, it.image,
              json.encode({ desc = it.desc, type = it.itype, rarity = it.rarity, attach = it.attach }) })
    end

    local rows = MySQL.query.await('SELECT * FROM items') or {}
    for _, r in ipairs(rows) do
        -- oxmysql returns TINYINT(1) as a boolean, so coerce the flags to 0/1 —
        -- otherwise `stackable == 1` / `usable == 1` silently fail everywhere.
        r.stackable = (r.stackable == true or r.stackable == 1) and 1 or 0
        r.usable    = (r.usable == true or r.usable == 1) and 1 or 0
        if type(r.metadata) == 'string' then r.metadata = json.decode(r.metadata) or {} end
        r.itype = r.metadata and r.metadata.type    -- weapon / ammo / backpack / armor / food / ...
        ItemDefs[r.name] = r
    end

    -- register use handlers by catalogue type
    for _, it in ipairs(InventoryItems or {}) do
        if it.usable == 1 and UseByType[it.itype] then
            local fn = UseByType[it.itype]
            UsableItems[it.name] = function(src, item) fn(src, item, ItemDefs[it.name]) end
        end
    end
end)

-- ── Container helpers ──────────────────────────────────────────
-- Treat nil AND an empty table as "no metadata" — in Lua `not {}` is false, so a
-- freshly-created item with metadata = {} would otherwise block every stack merge.
local function noMeta(m) return m == nil or (type(m) == 'table' and next(m) == nil) end

local function weightOf(items)
    local w = 0
    for _, it in ipairs(items) do
        local d = ItemDefs[it.name]
        if d then w = w + (d.weight * it.amount) end
    end
    return w
end

-- Carrying a backpack item raises the personal carry capacity.
local function hasBackpack(src)
    for _, it in ipairs(Inv[src] or {}) do
        if ItemDefs[it.name] and ItemDefs[it.name].itype == 'backpack' then return true end
    end
    return false
end
local function maxWeightFor(src) return Config.MaxWeight + (hasBackpack(src) and Config.Backpack.weight or 0) end
local function maxSlotsFor(src)  return Config.MaxSlots  + (hasBackpack(src) and Config.Backpack.slots  or 0) end

local function usedSlots(items)
    local u = {}
    for _, it in ipairs(items) do u[it.slot] = true end
    return u
end

local function freeSlot(items, maxSlots)
    local u = usedSlots(items)
    for i = 1, maxSlots do if not u[i] then return i end end
    return nil
end

local function itemAt(items, slot)
    for i, it in ipairs(items) do if it.slot == slot then return it, i end end
    return nil
end

--- Add an item into a container (respects stacking, slots, weight). Returns success.
--- preferredSlot (optional): drop it there if free / stack onto a match there.
local function addToContainer(items, name, amount, metadata, maxSlots, maxWeight, preferredSlot)
    local d = ItemDefs[name]
    if not d or amount <= 0 then return false end
    if weightOf(items) + (d.weight * amount) > maxWeight then return false end
    if d.stackable == 1 and noMeta(metadata) then
        -- prefer stacking onto the dropped slot, else onto the first matching stack
        local pref = preferredSlot and itemAt(items, preferredSlot)
        if pref and pref.name == name and noMeta(pref.metadata) then pref.amount = pref.amount + amount; return true end
        for _, it in ipairs(items) do
            if it.name == name and noMeta(it.metadata) then it.amount = it.amount + amount; return true end
        end
    end
    local used = usedSlots(items)
    local slot = (preferredSlot and preferredSlot >= 1 and preferredSlot <= maxSlots and not used[preferredSlot] and preferredSlot) or freeSlot(items, maxSlots)
    if not slot then return false end
    items[#items + 1] = { name = name, amount = amount, slot = slot, metadata = metadata }
    return true
end

local function removeFromSlot(items, slot, amount)
    local it, idx = itemAt(items, slot)
    if not it or amount <= 0 or amount > it.amount then return false end
    if amount == it.amount then table.remove(items, idx) else it.amount = it.amount - amount end
    return true
end

-- ── Player inventory sync ──────────────────────────────────────
local function syncPlayer(src)
    local player = Core.GetPlayer(src)
    if player then player.SetInventory(Inv[src]) end
end

-- The hidden pocket persists in the character's metadata, NOT the main inventory
-- array, so nothing that reads GetSearchable/GetItems (a police search, the shop
-- view, give/steal) can ever see it.
local function syncPocket(src)
    local player = Core.GetPlayer(src)
    if player then player.SetMetadata('pocket', Pocket[src] or {}) end
end

AddEventHandler('v-core:server:onPlayerLoaded', function(src, player)
    local saved = player.GetInventory()
    Inv[src] = (type(saved) == 'table' and saved[1] ~= nil or type(saved) == 'table') and saved or {}
    if type(Inv[src]) ~= 'table' then Inv[src] = {} end
    local pk = player.GetMetadata('pocket')
    Pocket[src] = (type(pk) == 'table') and pk or {}
end)

AddEventHandler('playerDropped', function()
    local src = source
    if Inv[src] then syncPlayer(src) end
    if Pocket[src] then syncPocket(src) end
    Inv[src] = nil
    Pocket[src] = nil
    OpenStash[src] = nil
    Equipped[src] = nil
    SearchTarget[src] = nil
    -- anyone frisking this player must stop
    for s, t in pairs(SearchTarget) do if t == src then SearchTarget[s] = nil; OpenStash[s] = nil end end
end)

-- ── Stash loading ──────────────────────────────────────────────
local function loadStash(id, maxSlots, maxWeight, persistent)
    if Stashes[id] then return Stashes[id] end
    local items = {}
    if persistent then
        local row = MySQL.single.await('SELECT items FROM stashes WHERE id = ?', { id })
        if row and row.items then items = (type(row.items) == 'table') and row.items or (json.decode(row.items) or {}) end
    end
    Stashes[id] = { items = items, maxSlots = maxSlots, maxWeight = maxWeight, persistent = persistent }
    return Stashes[id]
end

local function saveStash(id)
    local s = Stashes[id]
    if s and s.persistent then
        MySQL.insert('INSERT INTO stashes (id, items) VALUES (?, ?) ON DUPLICATE KEY UPDATE items = ?',
            { id, json.encode(s.items), json.encode(s.items) })
    end
end

-- Drop position is taken from the player's SERVER-side ped coords (not a
-- client-supplied point, which a modded client could place anywhere).
local function dropCoords(src)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return nil end
    local c = GetEntityCoords(ped)
    return { x = c.x + 0.0, y = c.y + 0.0, z = c.z + 0.0 }
end

-- Garbage-collect an emptied ground drop (fixes the unbounded `Stashes` growth)
-- and tell every client to remove its world prop.
local function gcDrop(id)
    if id and Stashes[id] and id:sub(1, 5) == 'drop:' and #Stashes[id].items == 0 then
        Stashes[id] = nil
        TriggerClientEvent('v-inventory:client:removeDrop', -1, id)
        return true
    end
    return false
end

-- ── State sent to the NUI ──────────────────────────────────────
-- `full` (only on the initial open) attaches the item catalogue (`defs`, ~170
-- rows). Every subsequent action re-renders from the returned state WITHOUT it —
-- the NUI caches defs from the open — so move/use/drop payloads stay small.
local function buildState(src, full)
    local secondary = nil
    local sid = OpenStash[src]
    if sid == 'search' and SearchTarget[src] and Inv[SearchTarget[src]] then
        local st = SearchTarget[src]
        secondary = { id = 'search', label = 'inv.search_title', kind = 'search',
                      items = Inv[st], maxWeight = maxWeightFor(st), maxSlots = maxSlotsFor(st) }
    elseif sid and Stashes[sid] then
        secondary = { id = sid, label = Stashes[sid].label or 'stash', kind = Stashes[sid].kind,
                      items = Stashes[sid].items, maxWeight = Stashes[sid].maxWeight, maxSlots = Stashes[sid].maxSlots }
    end
    local p = Core.GetPlayer(src)
    local equipment = nil
    if GetResourceState('v-clothing') == 'started' then
        local ok, worn = pcall(function() return exports['v-clothing']:GetWorn(src) end)
        if ok then equipment = worn end
    end
    return {
        defs      = full and ItemDefs or nil,
        maxWeight = maxWeightFor(src),
        maxSlots  = maxSlotsFor(src),
        hotbar    = Config.HotbarSlots,
        player    = { items = Inv[src] or {}, weight = weightOf(Inv[src] or {}),
                      cash = (p and p.money and p.money.cash) or 0 },
        pocket    = { items = Pocket[src] or {}, weight = weightOf(Pocket[src] or {}),
                      maxWeight = Config.Pocket.weight, maxSlots = Config.Pocket.slots },
        secondary = secondary,
        equipment = equipment,
    }
end

-- Never trust NUI amounts for cash: clamp to what the account actually holds.
local function clampCash(p, requested)
    if not p then return 0 end
    local n = math.floor(tonumber(requested) or 0)
    return math.max(0, math.min(n, p.money.cash))
end

Core.RegisterCallback('v-inventory:getState', function(source, resolve)
    resolve(buildState(source, true))   -- full: attach the catalogue once
end)

-- ── Move (player <-> secondary, or rearrange) ──────────────────
local function containerOf(src, key)
    if key == 'player' then return Inv[src], maxSlotsFor(src), maxWeightFor(src) end
    if key == 'pocket' then return Pocket[src], Config.Pocket.slots, Config.Pocket.weight end
    if key == 'secondary' then
        -- frisking another player: the "secondary" is the target's live inventory
        if OpenStash[src] == 'search' then
            local st = SearchTarget[src]
            if st and Inv[st] then return Inv[st], maxSlotsFor(st), maxWeightFor(st) end
            return nil
        end
        local sid = OpenStash[src]
        if sid and Stashes[sid] then return Stashes[sid].items, Stashes[sid].maxSlots, Stashes[sid].maxWeight end
    end
    return nil
end

-- Persist whichever of player / pocket / secondary a move touched.
local function persistMove(src, from, to)
    if from == 'player' or to == 'player' then syncPlayer(src) end
    if from == 'pocket' or to == 'pocket' then syncPocket(src) end
    if from == 'secondary' or to == 'secondary' then
        if OpenStash[src] == 'search' and SearchTarget[src] then
            syncPlayer(SearchTarget[src])   -- persist the frisked player's inventory
        else
            saveStash(OpenStash[src])
        end
    end
end

Core.RegisterCallback('v-inventory:move', function(source, resolve, data)
    -- While frisking a player, re-check they are still valid and nearby on every
    -- move, so you can't keep looting after walking away.
    if OpenStash[source] == 'search' then
        local st = SearchTarget[source]
        local ped, tped = GetPlayerPed(source), st and GetPlayerPed(st)
        if not st or not Inv[st] or not tped or tped == 0
           or #(GetEntityCoords(ped) - GetEntityCoords(tped)) > 3.5 then
            SearchTarget[source] = nil; OpenStash[source] = nil
            resolve(buildState(source)); return
        end
    end

    -- (A) Wallet cash -> a real container (drop/trunk/stash): withdraw + spawn item.
    if data.from == 'wallet' then
        local p = Core.GetPlayer(source)
        local toItems, toSlots, toWeight = containerOf(source, data.to)
        if not p or not toItems or data.to == 'wallet' or data.to == 'player' then resolve(false); return end
        local amount = clampCash(p, data.amount)
        if amount <= 0 then resolve(false); return end
        if not addToContainer(toItems, MONEY, amount, nil, toSlots, toWeight) then resolve({ error = 'space' }); return end
        p.RemoveMoney('cash', amount, 'inv-move')
        persistMove(source, 'wallet', data.to)
        resolve(buildState(source)); return
    end

    local fromItems, _, _ = containerOf(source, data.from)
    local toItems, toSlots, toWeight = containerOf(source, data.to)
    if not fromItems or not toItems then resolve(false); return end

    -- (B) A real money item -> the player wallet: deposit into the account, destroy item.
    do
        local mit = itemAt(fromItems, data.fromSlot)
        if mit and mit.name == MONEY and (data.to == 'wallet' or data.to == 'player') then
            local p = Core.GetPlayer(source)
            if not p then resolve(false); return end
            local amount = math.min(math.floor(tonumber(data.amount) or mit.amount), mit.amount)
            if amount <= 0 then resolve(false); return end
            removeFromSlot(fromItems, data.fromSlot, amount)
            p.AddMoney('cash', amount, 'inv-move')
            persistMove(source, data.from, 'wallet')
            resolve(buildState(source)); return
        end
    end

    local it = itemAt(fromItems, data.fromSlot)
    if not it then resolve(false); return end
    local amount = math.floor(math.min(tonumber(data.amount) or it.amount, it.amount))
    if amount <= 0 then resolve(false); return end

    -- moving the drawn weapon out of its slot -> holster it first
    if data.from == 'player' then maybeUnequip(source, data.fromSlot) end

    -- weight check for cross-container moves
    if data.from ~= data.to then
        local d = ItemDefs[it.name]
        if not d or weightOf(toItems) + (d.weight * amount) > toWeight then resolve({ error = 'weight' }); return end
        if not addToContainer(toItems, it.name, amount, it.metadata, toSlots, toWeight, data.toSlot) then resolve({ error = 'space' }); return end
        removeFromSlot(fromItems, data.fromSlot, amount)
    else
        -- same container: merge / swap / move / split
        local d = ItemDefs[it.name]
        local dest = data.toSlot
        local target = dest and itemAt(fromItems, dest)
        if target then
            if target.name == it.name and d and d.stackable == 1 and noMeta(it.metadata) and noMeta(target.metadata) then
                target.amount = target.amount + amount                    -- merge stacks
                removeFromSlot(fromItems, data.fromSlot, amount)
            elseif amount == it.amount then
                it.slot, target.slot = target.slot, it.slot               -- swap two items
            end
        else
            dest = dest or freeSlot(fromItems, toSlots)
            if dest then
                if amount >= it.amount then
                    it.slot = dest                                        -- move whole stack
                else
                    removeFromSlot(fromItems, data.fromSlot, amount)      -- split off a new stack
                    fromItems[#fromItems + 1] = { name = it.name, amount = amount, slot = dest, metadata = it.metadata }
                end
            end
        end
    end

    persistMove(source, data.from, data.to)
    -- a ground drop emptied by taking its last item -> garbage-collect it
    if data.from == 'secondary' then
        local sid = OpenStash[source]
        if gcDrop(sid) then OpenStash[source] = nil end
    end
    resolve(buildState(source))
end)

-- ── Weapons (equip / ammo / serial) ────────────────────────────
local function genSerial()
    local chars, s = 'ABCDEFGHJKLMNPQRSTUVWXYZ0123456789', ''
    for _ = 1, 8 do local i = math.random(1, #chars); s = s .. chars:sub(i, i) end
    return s
end

-- If the given slot holds the currently-drawn weapon, holster it (the client
-- reports the remaining ammo back before removing it). Called before a weapon
-- item is moved / dropped / given so the ped never keeps a gone weapon.
local function maybeUnequip(src, slot)
    local eq = Equipped[src]
    if eq and eq.slot == slot then
        Equipped[src] = nil
        TriggerClientEvent('v-inventory:client:unequipWeapon', src, slot, eq.name)
    end
end

-- Client reports a weapon's live ammo (on holster / periodically) -> persist it.
RegisterNetEvent('v-inventory:server:weaponAmmo', function(slot, ammo)
    local src = source
    local it = itemAt(Inv[src] or {}, slot)
    if it and ItemDefs[it.name] and ItemDefs[it.name].itype == 'weapon' then
        it.metadata = it.metadata or {}
        it.metadata.ammo = math.max(0, math.floor(tonumber(ammo) or 0))
        syncPlayer(src)
    end
end)

-- ── Use ────────────────────────────────────────────────────────
Core.RegisterCallback('v-inventory:use', function(source, resolve, slot)
    local it = itemAt(Inv[source] or {}, slot)
    if not it then resolve(false); return end
    local d = ItemDefs[it.name]
    if not d or d.usable ~= 1 then resolve(false); return end
    local itype = d.itype

    -- Weapon: toggle equip/unequip (never consumed). Serial minted on first draw.
    if itype == 'weapon' then
        local eq = Equipped[source]
        if eq and eq.slot == slot then
            Equipped[source] = nil
            TriggerClientEvent('v-inventory:client:unequipWeapon', source, slot, it.name)
        else
            if eq then TriggerClientEvent('v-inventory:client:unequipWeapon', source, eq.slot, eq.name) end
            it.metadata = it.metadata or {}
            it.metadata.serial = it.metadata.serial or genSerial()
            Equipped[source] = { slot = slot, name = it.name }
            TriggerClientEvent('v-inventory:client:equipWeapon', source,
                { slot = slot, name = it.name, ammo = it.metadata.ammo or 0, serial = it.metadata.serial,
                  attachments = it.metadata.attachments })
        end
        syncPlayer(source)
        resolve(buildState(source)); return
    end

    -- Weapon attachment: fit it to the drawn weapon (consumed), stored on the weapon
    -- item's metadata so it re-applies on every future draw.
    if itype == 'attachment' then
        local eq = Equipped[source]
        if not eq then Core.Notify(source, LP(source, 'inv.no_weapon'), 'error'); resolve(false); return end
        local kind = d.metadata and d.metadata.attach
        local comp = kind and ComponentFor(eq.name, kind)
        if not comp then Core.Notify(source, LP(source, 'inv.attach_nofit'), 'error'); resolve(false); return end
        local w = itemAt(Inv[source] or {}, eq.slot)
        if not w then resolve(false); return end
        w.metadata = w.metadata or {}
        w.metadata.attachments = w.metadata.attachments or {}
        if w.metadata.attachments[kind] then
            Core.Notify(source, LP(source, 'inv.attach_dupe'), 'error'); resolve(false); return
        end
        w.metadata.attachments[kind] = comp
        TriggerClientEvent('v-inventory:client:applyAttachment', source, comp)
        removeFromSlot(Inv[source], slot, 1)
        syncPlayer(source)
        Core.Notify(source, LP(source, 'inv.attach_ok', d.label), 'success')
        resolve(buildState(source)); return
    end

    -- Ammo: top up the drawn weapon (consumes one box).
    if itype == 'ammo' then
        local eq = Equipped[source]
        if not eq then Core.Notify(source, LP(source, 'inv.no_weapon'), 'error'); resolve(false); return end
        TriggerClientEvent('v-inventory:client:giveAmmo', source, eq.name, Config.AmmoPerItem or 30)
        removeFromSlot(Inv[source], slot, 1)
        syncPlayer(source)
        resolve(buildState(source)); return
    end

    -- Body armor.
    if itype == 'armor' then
        TriggerClientEvent('v-inventory:client:applyArmor', source, Config.ArmorAmount or 100)
        removeFromSlot(Inv[source], slot, 1)
        syncPlayer(source)
        Core.Notify(source, LP(source, 'inv.used', d.label), 'success')
        resolve(buildState(source)); return
    end

    -- Default consumable (food / drink / drug / medical / ...).
    local handler = UsableItems[it.name]
    if handler then handler(source, it) end
    removeFromSlot(Inv[source], slot, 1)
    syncPlayer(source)
    Core.Notify(source, LP(source, 'inv.used', d.label), 'success')
    resolve(buildState(source))
end)

-- ── Equipment: unequip a worn clothing category (via v-clothing) ──
Core.RegisterCallback('v-inventory:unequipCloth', function(source, resolve, cat)
    if GetResourceState('v-clothing') ~= 'started' or type(cat) ~= 'string' then resolve(false); return end
    pcall(function() exports['v-clothing']:Unequip(source, cat) end)
    resolve(buildState(source))
end)

-- ── Rename an item (custom label stored in its metadata) ───────
Core.RegisterCallback('v-inventory:rename', function(source, resolve, data)
    local items = containerOf(source, data.inv or 'player')
    if not items then resolve(false); return end
    local it = itemAt(items, data.slot)
    if not it or it.name == MONEY then resolve(false); return end
    local name = tostring(data.name or ''):gsub('[\r\n\t]', ''):sub(1, 30)
    it.metadata = it.metadata or {}
    it.metadata.label = (name ~= '' and name) or nil
    if (data.inv or 'player') == 'secondary' then saveStash(OpenStash[source]) else syncPlayer(source) end
    resolve(buildState(source))
end)

-- ── Drop (create / add to a ground stash near the player) ──────
Core.RegisterCallback('v-inventory:drop', function(source, resolve, data)
    -- Dropping cash from the wallet: charge the account first, then spawn a real item.
    if data.money then
        local p = Core.GetPlayer(source)
        local amount = clampCash(p, data.amount)
        if amount <= 0 then resolve(false); return end
        if not p.RemoveMoney('cash', amount, 'drop') then resolve(false); return end
        local at = dropCoords(source); if not at then resolve(false); return end
        dropCounter = dropCounter + 1
        local id = 'drop:' .. dropCounter
        local stash = loadStash(id, Config.Drop.slots, Config.Drop.weight, false)
        stash.label, stash.coords = 'ground', at
        addToContainer(stash.items, MONEY, amount, nil, Config.Drop.slots, Config.Drop.weight)
        TriggerClientEvent('v-inventory:client:createDrop', -1, id, at)
        resolve(buildState(source)); return
    end

    local it = itemAt(Inv[source] or {}, data.slot)
    if not it then resolve(false); return end
    local amount = math.floor(math.min(tonumber(data.amount) or it.amount, it.amount))
    if amount <= 0 then resolve(false); return end
    maybeUnequip(source, data.slot)   -- holster if dropping the drawn weapon
    local at = dropCoords(source); if not at then resolve(false); return end
    dropCounter = dropCounter + 1
    local id = 'drop:' .. dropCounter
    local stash = loadStash(id, Config.Drop.slots, Config.Drop.weight, false)
    stash.label, stash.coords = 'ground', at
    addToContainer(stash.items, it.name, amount, it.metadata, Config.Drop.slots, Config.Drop.weight)
    removeFromSlot(Inv[source], data.slot, amount)
    syncPlayer(source)
    TriggerClientEvent('v-inventory:client:createDrop', -1, id, at)
    resolve(buildState(source))
end)

-- ── Give (to nearest player) ───────────────────────────────────
Core.RegisterCallback('v-inventory:give', function(source, resolve, data)
    local target = tonumber(data.target)

    -- Giving cash from the wallet: account -> account (never touches the arrays).
    if data.money then
        local p  = Core.GetPlayer(source)
        local tp = target and Core.GetPlayer(target)
        if not tp then resolve({ error = 'target' }); return end
        local amount = clampCash(p, data.amount)
        if amount <= 0 then resolve(false); return end
        if not p.RemoveMoney('cash', amount, 'give') then resolve(false); return end
        tp.AddMoney('cash', amount, 'give')
        Core.Notify(source, LP(source, 'inv.gave', amount, 'Cash'), 'success')
        Core.Notify(target, LP(target, 'inv.received', amount, 'Cash'), 'info')
        resolve(buildState(source)); return
    end

    local it = itemAt(Inv[source] or {}, data.slot)
    if not target or not it or not Inv[target] then resolve({ error = 'target' }); return end
    local amount = math.floor(math.min(tonumber(data.amount) or it.amount, it.amount))
    if amount <= 0 then resolve(false); return end
    maybeUnequip(source, data.slot)   -- holster if giving away the drawn weapon
    local d = ItemDefs[it.name]
    if not addToContainer(Inv[target], it.name, amount, it.metadata, maxSlotsFor(target), maxWeightFor(target)) then
        resolve({ error = 'space' }); return
    end
    removeFromSlot(Inv[source], data.slot, amount)
    syncPlayer(source); syncPlayer(target)
    Core.Notify(source, LP(source, 'inv.gave', amount, d.label), 'success')
    Core.Notify(target, LP(target, 'inv.received', amount, d.label), 'info')
    resolve(buildState(source))
end)

-- ── Open a secondary container (trunk / glovebox / ground) ─────
-- Server-authoritative: the client NEVER supplies a stash id for a vehicle. It
-- sends the vehicle's net id; the server resolves the entity, checks the player
-- is next to it, and derives the id from the plate. This closes the old exploit
-- (open any trunk by plate from anywhere / write arbitrary `stashes` rows).
RegisterNetEvent('v-inventory:server:openStash', function(payload, label, kind)
    local src = source
    if kind == 'trunk' or kind == 'glovebox' then
        local netId = tonumber(payload)
        if not netId then return end
        local veh = NetworkGetEntityFromNetworkId(netId)
        if not veh or veh == 0 or not DoesEntityExist(veh) then return end
        local ped = GetPlayerPed(src)
        if ped == 0 or #(GetEntityCoords(ped) - GetEntityCoords(veh)) > 5.0 then return end
        local plate = (GetVehicleNumberPlateText(veh) or ''):gsub('%s+', '')
        if plate == '' then return end
        local cfg = (kind == 'glovebox') and Config.Glovebox or Config.Trunk
        local id  = kind .. ':' .. plate
        local s = loadStash(id, cfg.slots, cfg.weight, true)
        s.label, s.kind = label or kind, kind
        OpenStash[src] = id
        TriggerClientEvent('v-inventory:client:openSecondary', src)
    elseif kind == 'drop' then
        local id = tostring(payload or '')
        if not id:match('^drop:%d+$') or not Stashes[id] then return end   -- must be a real ground drop
        Stashes[id].kind = 'drop'
        OpenStash[src] = id
        TriggerClientEvent('v-inventory:client:openSecondary', src)
    end
end)

RegisterNetEvent('v-inventory:server:closeStash', function()
    gcDrop(OpenStash[source])   -- clean up an emptied ground drop on close
    OpenStash[source] = nil
    SearchTarget[source] = nil
end)

-- ── Frisk / steal a nearby player (RP) ─────────────────────────
-- Only a target who is HANDS-UP, downed, or being searched by police/admin can
-- be frisked. Proximity is validated server-side; only the SEARCHABLE inventory
-- (main items — never the hidden pocket) is exposed.
RegisterNetEvent('v-inventory:server:searchPlayer', function(targetSrc)
    local src = source
    targetSrc = tonumber(targetSrc)
    if not targetSrc or targetSrc == src or not Inv[targetSrc] then return end
    local ped, tped = GetPlayerPed(src), GetPlayerPed(targetSrc)
    if ped == 0 or tped == 0 or #(GetEntityCoords(ped) - GetEntityCoords(tped)) > 3.0 then return end

    local downed  = GetEntityHealth(tped) <= 101
    local handsUp = Player(targetSrc).state.handsup == true
    local police  = Core.HasPermission(src, 'admin')   -- TODO: police job when v-jobs lands
    if not (downed or handsUp or police) then
        Core.Notify(src, LP(src, 'inv.cant_search'), 'error'); return
    end

    SearchTarget[src] = targetSrc
    OpenStash[src] = 'search'
    Core.Notify(targetSrc, LP(targetSrc, 'inv.being_searched'), 'warning')
    TriggerClientEvent('v-inventory:client:openSecondary', src)
end)

-- ── Shared / gang stashes (permission-gated, persistent) ───────
-- Access is verified server-side on every open. Open from a target zone / job
-- menu via the net event, or from another resource via the export.
local function openShared(src, id)
    local cfg = Config.SharedStashes and Config.SharedStashes[id]
    local p = Core.GetPlayer(src)
    if not cfg or not p then return false end
    local ok = true
    if cfg.job then ok = p.job and p.job.name == cfg.job and (p.job.grade or 0) >= (cfg.minGrade or 0) end
    if ok and cfg.gang then ok = p.gang and p.gang.name == cfg.gang and (p.gang.grade or 0) >= (cfg.minGrade or 0) end
    if ok and cfg.permission then ok = Core.HasPermission(src, cfg.permission) end
    if not ok then Core.Notify(src, LP(src, 'inv.no_access'), 'error'); return false end
    local sid = 'shared:' .. id
    local s = loadStash(sid, cfg.slots or 50, cfg.weight or 500000, true)
    s.label, s.kind = cfg.label or id, 'stash'
    OpenStash[src] = sid
    TriggerClientEvent('v-inventory:client:openSecondary', src)
    return true
end
RegisterNetEvent('v-inventory:server:openSharedStash', function(id) openShared(source, tostring(id or '')) end)
exports('OpenSharedStash', function(src, id) return openShared(src, tostring(id or '')) end)

-- ── Server exports (used by shops / jobs / other modules) ──────
exports('AddItem', function(src, name, amount, metadata, slot)
    if not Inv[src] then return false end
    local ok = addToContainer(Inv[src], name, amount, metadata, maxSlotsFor(src), maxWeightFor(src), slot)
    if ok then syncPlayer(src) end
    return ok
end)

exports('RemoveItem', function(src, name, amount)
    if not Inv[src] then return false end
    amount = amount or 1
    for _, it in ipairs(Inv[src]) do
        if it.name == name and it.amount >= amount then
            removeFromSlot(Inv[src], it.slot, amount); syncPlayer(src); return true
        end
    end
    return false
end)

exports('GetItemCount', function(src, name)
    local n = 0
    for _, it in ipairs(Inv[src] or {}) do if it.name == name then n = n + it.amount end end
    return n
end)

exports('RegisterUsableItem', function(name, handler) UsableItems[name] = handler end)

-- Read-only helpers for other modules (e.g. the shop's inventory-view panel).
exports('GetLimits', function() return { maxSlots = Config.MaxSlots, maxWeight = Config.MaxWeight, hotbar = Config.HotbarSlots } end)
exports('GetItems', function(src) return Inv[src] or {} end)

-- What a police search / steal is allowed to see: the MAIN inventory only.
-- The hidden pocket lives in metadata and is deliberately excluded here, so no
-- search feature can reveal it. Use this (not GetItems) from any frisk/steal code.
exports('GetSearchable', function(src) return Inv[src] or {} end)

-- ── Live cash mirror: refresh an open inventory when the account changes ──
AddEventHandler('v-core:server:onMoneyChange', function(src, account, amount)
    if account == 'cash' and Inv[src] then
        TriggerClientEvent('v-inventory:client:cash', src, amount)
    end
end)

-- ── Admin: /giveitem <id> <name> <amount> (permission-gated; players use no commands) ──
RegisterCommand('giveitem', function(source, args)
    if source ~= 0 and not Core.HasPermission(source, 'admin') then return end
    local target = tonumber(args[1]) or source
    local name = args[2]
    local amount = tonumber(args[3]) or 1
    if not name or not ItemDefs[name] or not Inv[target] then return end
    if addToContainer(Inv[target], name, amount, nil, maxSlotsFor(target), maxWeightFor(target)) then
        syncPlayer(target)
        Core.Notify(target, ('+%dx %s'):format(amount, ItemDefs[name].label), 'success')
    end
end, false)
