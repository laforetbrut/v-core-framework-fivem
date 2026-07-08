-- v-inventory | server
-- Items live as an array: { name, amount, slot, metadata }.
-- 'player' container = the v-core player inventory (synced back for saving).
-- secondary containers (trunk / glovebox / gang stash / ground) live in `Stashes`.
local Core = exports['v-core']:GetCore()

local ItemDefs    = {}   -- name -> row
local Inv         = {}   -- [source] = items[]
local Stashes     = {}   -- [id]     = { items, maxWeight, maxSlots, persistent }
local OpenStash   = {}   -- [source] = stash id currently open
local UsableItems = {}   -- name -> handler(src, item)
local dropCounter = 0

-- ── Item definitions ───────────────────────────────────────────
CreateThread(function()
    while GetResourceState('oxmysql') ~= 'started' do Wait(100) end
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS stashes (
        id VARCHAR(64) NOT NULL PRIMARY KEY,
        items JSON NOT NULL,
        updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
    local rows = MySQL.query.await('SELECT * FROM items') or {}
    for _, r in ipairs(rows) do ItemDefs[r.name] = r end
end)

-- ── Container helpers ──────────────────────────────────────────
local function weightOf(items)
    local w = 0
    for _, it in ipairs(items) do
        local d = ItemDefs[it.name]
        if d then w = w + (d.weight * it.amount) end
    end
    return w
end

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
local function addToContainer(items, name, amount, metadata, maxSlots, maxWeight)
    local d = ItemDefs[name]
    if not d or amount <= 0 then return false end
    if weightOf(items) + (d.weight * amount) > maxWeight then return false end
    if d.stackable == 1 and not metadata then
        for _, it in ipairs(items) do
            if it.name == name and not it.metadata then it.amount = it.amount + amount; return true end
        end
    end
    local slot = freeSlot(items, maxSlots)
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

AddEventHandler('v-core:server:onPlayerLoaded', function(src, player)
    local saved = player.GetInventory()
    Inv[src] = (type(saved) == 'table' and saved[1] ~= nil or type(saved) == 'table') and saved or {}
    if type(Inv[src]) ~= 'table' then Inv[src] = {} end
end)

AddEventHandler('playerDropped', function()
    local src = source
    if Inv[src] then syncPlayer(src) end
    Inv[src] = nil
    OpenStash[src] = nil
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

-- ── State sent to the NUI ──────────────────────────────────────
local function buildState(src)
    local secondary = nil
    local sid = OpenStash[src]
    if sid and Stashes[sid] then
        secondary = { id = sid, label = Stashes[sid].label or 'stash',
                      items = Stashes[sid].items, maxWeight = Stashes[sid].maxWeight }
    end
    return {
        defs      = ItemDefs,
        maxWeight = Config.MaxWeight,
        maxSlots  = Config.MaxSlots,
        player    = { items = Inv[src] or {}, weight = weightOf(Inv[src] or {}) },
        secondary = secondary,
    }
end

Core.RegisterCallback('v-inventory:getState', function(source, resolve)
    resolve(buildState(source))
end)

-- ── Move (player <-> secondary, or rearrange) ──────────────────
local function containerOf(src, key)
    if key == 'player' then return Inv[src], Config.MaxSlots, Config.MaxWeight end
    local sid = OpenStash[src]
    if key == 'secondary' and sid and Stashes[sid] then
        return Stashes[sid].items, Stashes[sid].maxSlots, Stashes[sid].maxWeight
    end
    return nil
end

Core.RegisterCallback('v-inventory:move', function(source, resolve, data)
    local fromItems, _, _ = containerOf(source, data.from)
    local toItems, toSlots, toWeight = containerOf(source, data.to)
    if not fromItems or not toItems then resolve(false); return end

    local it = itemAt(fromItems, data.fromSlot)
    if not it then resolve(false); return end
    local amount = math.min(tonumber(data.amount) or it.amount, it.amount)
    if amount <= 0 then resolve(false); return end

    -- weight check for cross-container moves
    if data.from ~= data.to then
        local d = ItemDefs[it.name]
        if not d or weightOf(toItems) + (d.weight * amount) > toWeight then resolve({ error = 'weight' }); return end
        if not addToContainer(toItems, it.name, amount, it.metadata, toSlots, toWeight) then resolve({ error = 'space' }); return end
        removeFromSlot(fromItems, data.fromSlot, amount)
    else
        -- same container: place onto target slot (swap/merge) or a specific slot
        local target = data.toSlot and itemAt(fromItems, data.toSlot)
        if target and target.name == it.name and (ItemDefs[it.name] and ItemDefs[it.name].stackable == 1) and not it.metadata and not target.metadata then
            target.amount = target.amount + amount
            removeFromSlot(fromItems, data.fromSlot, amount)
        elseif data.toSlot and not target and amount == it.amount then
            it.slot = data.toSlot
        end
    end

    if data.from == 'player' or data.to == 'player' then syncPlayer(source) end
    if data.from == 'secondary' or data.to == 'secondary' then saveStash(OpenStash[source]) end
    resolve(buildState(source))
end)

-- ── Use ────────────────────────────────────────────────────────
Core.RegisterCallback('v-inventory:use', function(source, resolve, slot)
    local it = itemAt(Inv[source] or {}, slot)
    if not it then resolve(false); return end
    local d = ItemDefs[it.name]
    if not d or d.usable ~= 1 then resolve(false); return end
    local handler = UsableItems[it.name]
    if handler then handler(source, it) end
    removeFromSlot(Inv[source], slot, 1)
    syncPlayer(source)
    Core.Notify(source, LP(source, 'inv.used', d.label), 'success')
    resolve(buildState(source))
end)

-- ── Drop (create / add to a ground stash near the player) ──────
Core.RegisterCallback('v-inventory:drop', function(source, resolve, data)
    local it = itemAt(Inv[source] or {}, data.slot)
    if not it then resolve(false); return end
    local amount = math.min(tonumber(data.amount) or it.amount, it.amount)
    dropCounter = dropCounter + 1
    local id = 'drop:' .. dropCounter
    local stash = loadStash(id, Config.Drop.slots, Config.Drop.weight, false)
    stash.label = 'ground'
    addToContainer(stash.items, it.name, amount, it.metadata, Config.Drop.slots, Config.Drop.weight)
    removeFromSlot(Inv[source], data.slot, amount)
    syncPlayer(source)
    TriggerClientEvent('v-inventory:client:createDrop', -1, id, data.coords)
    resolve(buildState(source))
end)

-- ── Give (to nearest player) ───────────────────────────────────
Core.RegisterCallback('v-inventory:give', function(source, resolve, data)
    local target = tonumber(data.target)
    local it = itemAt(Inv[source] or {}, data.slot)
    if not target or not it or not Inv[target] then resolve({ error = 'target' }); return end
    local amount = math.min(tonumber(data.amount) or it.amount, it.amount)
    local d = ItemDefs[it.name]
    if not addToContainer(Inv[target], it.name, amount, it.metadata, Config.MaxSlots, Config.MaxWeight) then
        resolve({ error = 'space' }); return
    end
    removeFromSlot(Inv[source], data.slot, amount)
    syncPlayer(source); syncPlayer(target)
    Core.Notify(source, LP(source, 'inv.gave', amount, d.label), 'success')
    Core.Notify(target, LP(target, 'inv.received', amount, d.label), 'info')
    resolve(buildState(source))
end)

-- ── Open a secondary container (trunk / glovebox / gang / ground) ──
RegisterNetEvent('v-inventory:server:openStash', function(id, label, kind)
    local src = source
    local cfg = ({ trunk = Config.Trunk, glovebox = Config.Glovebox, drop = Config.Drop })[kind] or Config.Trunk
    local persistent = kind ~= 'drop'
    local s = loadStash(id, cfg.slots, cfg.weight, persistent)
    s.label = label or kind
    OpenStash[src] = id
    TriggerClientEvent('v-inventory:client:openSecondary', src)
end)

RegisterNetEvent('v-inventory:server:closeStash', function()
    OpenStash[source] = nil
end)

-- ── Server exports (used by shops / jobs / other modules) ──────
exports('AddItem', function(src, name, amount, metadata)
    if not Inv[src] then return false end
    local ok = addToContainer(Inv[src], name, amount, metadata, Config.MaxSlots, Config.MaxWeight)
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

-- ── Default usable items (hook to v-status) ────────────────────
local function status(src, key, delta)
    pcall(function() exports['v-status']:Add(src, key, delta) end)
end
UsableItems['water']   = function(src) status(src, 'thirst', 35) end
UsableItems['bread']   = function(src) status(src, 'hunger', 35) end
UsableItems['bandage'] = function(src)
    pcall(function() local s = exports['v-status']:Get(src); if s then exports['v-status']:SetBleed(src, math.max(0, (s.bleed or 0) - 1)) end end)
end

-- ── Admin: /giveitem <id> <name> <amount> (permission-gated; players use no commands) ──
RegisterCommand('giveitem', function(source, args)
    if source ~= 0 and not Core.HasPermission(source, 'admin') then return end
    local target = tonumber(args[1]) or source
    local name = args[2]
    local amount = tonumber(args[3]) or 1
    if not name or not ItemDefs[name] or not Inv[target] then return end
    if addToContainer(Inv[target], name, amount, nil, Config.MaxSlots, Config.MaxWeight) then
        syncPlayer(target)
        Core.Notify(target, ('+%dx %s'):format(amount, ItemDefs[name].label), 'success')
    end
end, false)
