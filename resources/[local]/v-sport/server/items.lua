--[[
    server/items.lua

    The consumables from Config.Items - whey first among them.

    ---------------------------------------------------------------------------------------
    WHAT THIS FILE DOES AND DELIBERATELY DOES NOT DO
    ---------------------------------------------------------------------------------------

    It registers a USE handler for each configured item, on whichever framework is running.

    It does NOT create the items. Creating an item means writing into qb-core's `items.lua`,
    or ESX's `items` table, or ox_inventory's `data/items.lua` - all of which belong to
    somebody else's resource. A script that silently edited one of those would break on their
    next update and leave you wondering why.

    ITEMS.md walks through adding them, framework by framework, with the exact blocks to
    paste. It takes about two minutes.

    An item that is configured here but does not exist in your inventory costs nothing: the
    handler is registered, nobody can ever have one, and it is never called.
]]

Items = {}

local function started(resource)
    local state = GetResourceState(resource)
    return state == 'started' or state == 'starting'
end

-- ---------------------------------------------------------------------------------------
-- Effects
-- ---------------------------------------------------------------------------------------

--- The message shown after a successful use. Translated when the config named a locale key,
--- used verbatim when it did not.
local function notify(src, entry, ...)
    local text = entry.notify
    if type(text) ~= 'string' or text == '' then return end
    Bridge.notify(src, Locale.text(text, ...), 'success')
end

--[[
    Apply one item's effect. Returns whether it did anything.

    A `false` return means the item is NOT consumed - taking whey when your allowance is
    already full should not eat the item. That decision is made per effect below, and it is
    the difference between an item that feels fair and one that feels like a scam.
]]
local function applyEffect(src, key, entry)
    local profile = Profiles.get(src)
    if not profile then return false end

    local effect = entry.effect
    local amount = tonumber(entry.amount) or 0
    local duration = math.max(0, tonumber(entry.duration) or 0)

    -- --- Whey ---------------------------------------------------------------------------
    if effect == 'recovery' then
        -- Already on the shortened window with more time left than this would give? Refuse,
        -- rather than quietly wasting the item.
        local now = Sport.now()
        local remaining = (tonumber(profile.recoveryUntil) or 0) - now
        if remaining >= duration then
            Bridge.notify(src, L('item.no_effect'), 'error')
            return false
        end

        Profiles.reduceRecovery(src, duration > 0 and duration or Config.Allowance.window)
        notify(src, entry, Sport.duration(Stats.allowanceWindow(true)))

        TriggerEvent('vsport:server:ItemUsed', src, key, 'recovery')
        return true
    end

    -- --- Allowance refund ---------------------------------------------------------------
    if effect == 'allowance' then
        local spent = Profiles.allowanceSpent(profile)
        if (spent.total or 0) <= 0 then
            Bridge.notify(src, L('item.no_effect'), 'error')
            return false
        end

        Profiles.refundAllowance(src, amount)
        notify(src, entry, amount)

        TriggerEvent('vsport:server:ItemUsed', src, key, 'allowance')
        return true
    end

    -- --- Training multiplier --------------------------------------------------------------
    if effect == 'multiplier' then
        Profiles.addMultiplier(src, entry.stat, amount > 0 and amount or 1.5, duration,
            'item:' .. key)
        notify(src, entry, amount, Sport.duration(duration))

        TriggerEvent('vsport:server:ItemUsed', src, key, 'multiplier')
        return true
    end

    -- --- Temporary points -----------------------------------------------------------------
    if effect == 'buff' then
        if not Stats.def(entry.stat) then
            Sport.warn(("Config.Items.%s has effect 'buff' but no valid stat"):format(key))
            return false
        end

        Profiles.addBuff(src, entry.stat, amount, duration, 'item:' .. key)
        notify(src, entry, amount, Sport.duration(duration))

        TriggerEvent('vsport:server:ItemUsed', src, key, 'buff')
        return true
    end

    -- --- Decay protection -------------------------------------------------------------------
    if effect == 'decay_pause' then
        local profileImmune = tonumber(profile.decayImmuneUntil) or 0
        if profileImmune - Sport.now() >= duration then
            Bridge.notify(src, L('item.no_effect'), 'error')
            return false
        end

        exports[Sport.resource]:SetDecayImmunity(src, duration)
        notify(src, entry, Sport.duration(duration))

        TriggerEvent('vsport:server:ItemUsed', src, key, 'decay_pause')
        return true
    end

    -- --- Stamina ----------------------------------------------------------------------------
    if effect == 'stamina' then
        TriggerClientEvent('vsport:client:RestoreStamina', src,
            Sport.clamp(amount, 0.0, 1.0, 1.0))
        notify(src, entry)

        TriggerEvent('vsport:server:ItemUsed', src, key, 'stamina')
        return true
    end

    Sport.warn(("Config.Items.%s has an unknown effect '%s'"):format(key, tostring(effect)))
    return false
end

--[[
    The whole use path: cooldown, effect, consume.

    Called by every framework's handler below, so the behaviour is identical on all of them.
    Returns whether the item should be consumed.
]]
function Items.use(src, key)
    local entry = Config.Items[key]
    if type(entry) ~= 'table' or entry.item == '' then return false end

    local profile = Profiles.get(src)
    if not profile then return false end

    -- Cooldown.
    local cooldown = math.max(0, tonumber(entry.cooldown) or 0)
    if cooldown > 0 then
        local until_ = tonumber(profile.itemCooldowns[key]) or 0
        local left = until_ - Sport.now()

        if left > 0 then
            Bridge.notify(src, L('item.cooldown', Sport.duration(left)), 'error')
            return false
        end
    end

    if not applyEffect(src, key, entry) then return false end

    if cooldown > 0 then
        profile.itemCooldowns[key] = Sport.now() + cooldown
    end

    Sport.debug(('%s used %s'):format(GetPlayerName(src) or src, entry.item))
    return entry.consume ~= false
end

-- ---------------------------------------------------------------------------------------
-- Registration
-- ---------------------------------------------------------------------------------------
--
-- Each framework wants its usable items registered a different way, and ox_inventory wants
-- them registered against itself rather than against the framework. All four paths are
-- attempted; the ones whose resource is not running do nothing.

local function registerQb(key, entry)
    local core = Bridge.core()
    if not core then return false end

    --[[
        INDEXED BEHIND A pcall, because `core` is not always a plain table.

        On ox_core, Bridge.core() is an exports object, and indexing an exports object with a key it
        does not have RAISES rather than returning nil. So `core.Functions` threw, the error escaped
        the registration loop, and every item after this one in the loop was never registered -
        including on frameworks where a later registrar would have worked.

        A probe for "does this core have qb-core's shape" has to be able to answer no.
    ]]
    local ok, functions = pcall(function() return core.Functions end)
    if not ok or type(functions) ~= 'table' then return false end

    -- This path already worked, and that is the evidence that broke the qb-core stat bug open:
    -- a truthiness test plus a pcall calls a proxied method quite happily. The player lookup
    -- next door gated on type and failed on the same object, in the same boot.
    local create = functions.CreateUseableItem
    if not Sport.callable(create) then return false end

    local ok = pcall(create, entry.item, function(source_)
        if Items.use(source_, key) and entry.consume ~= false then
            local player = Bridge.player(source_)
            if player and player.Functions and player.Functions.RemoveItem then
                pcall(player.Functions.RemoveItem, entry.item, 1)
                TriggerClientEvent('inventory:client:ItemBox', source_, entry.item, 'remove')
            end
        end
    end)

    return ok
end

local function registerEsx(key, entry)
    local core = Bridge.core()
    if not core then return false end

    -- Behind a pcall for the same reason as registerQb above: on ox_core the core object is an
    -- exports table and reading a key it does not have RAISES. This one was found by the check
    -- script's new guard rather than by anybody reading the file - the same mistake twice, ten
    -- lines apart, with the reason written between them.
    local ok, register = pcall(function() return core.RegisterUsableItem end)

    -- Sport.callable, not a type test. ESX's method read off the shared object is a callable
    -- table once it has crossed a resource boundary, and a type test here silently registered
    -- no items at all - the same defect that stopped every stat loading on qb-core.
    if not ok or not Sport.callable(register) then return false end

    return pcall(register, entry.item, function(source_)
        if Items.use(source_, key) and entry.consume ~= false then
            local player = Bridge.player(source_)
            if player and player.removeInventoryItem then
                pcall(player.removeInventoryItem, entry.item, 1)
            end
        end
    end)
end

--[[
    ox_inventory.

    ONE handler for every item rather than one per item: ox_inventory fires the same event
    for everything used, so a handler per configured item would mean four handlers all
    checking the same string. The item name is looked up in a map instead.

    ox_inventory removes the item itself when it is declared with `consume = 1` in its own
    data file, so nothing is removed here.
]]
local oxItems = {}              -- item name -> config key

local function registerOxInventory()
    if not started('ox_inventory') then return false end

    AddEventHandler('ox_inventory:usedItem', function(src, name)
        local key = oxItems[name]
        if key then Items.use(src, key) end
    end)

    return true
end

--[[
    v-inventory (this framework's inventory).

    It removes the used item ITSELF after the handler returns, so the handler only fires the
    effect and never removes - which is exactly right here, because every sport item is
    `consume = true`. The handler shape is function(src, item), matching v-inventory's dispatch.
]]
local function registerVInventory(key, entry)
    if not started('v-inventory') then return false end
    return pcall(function()
        exports['v-inventory']:RegisterUsableItem(entry.item, function(source_)
            -- v-inventory takes the item out itself, unless the handler answers false. So
            -- a refused use - an effect already running, a cooldown - keeps the item, which
            -- is what the qb path has always done and what Items.use's return value means.
            return Items.use(source_, key) and entry.consume ~= false
        end)
    end)
end

CreateThread(function()
    -- Let the framework and the inventory finish starting. Registering a usable item against
    -- a resource that has not booted silently does nothing on every one of them.
    Wait(4000)

    local registered = 0

    for key, entry in pairs(Config.Items) do
        if type(entry) == 'table' and type(entry.item) == 'string' and entry.item ~= '' then
            oxItems[entry.item] = key

            -- v-inventory first: it is the framework's own inventory and the one that answers here.
            local ok = registerVInventory(key, entry)
            if not ok then ok = registerQb(key, entry) end
            if not ok then ok = registerEsx(key, entry) end
            if ok then registered = registered + 1 end
        end
    end

    if registerOxInventory() then
        Sport.debug('listening for ox_inventory:usedItem')
    end

    if registered > 0 then
        Sport.print(('registered %d usable items'):format(registered))
    end

    Sport.print('items must exist in your inventory before players can hold them - see ITEMS.md')
end)

--[[
    The universal fallback.

    A server whose inventory this resource does not know about can call this from its own use
    handler and get identical behaviour:

        exports['v-sport']:UseItem(source, 'whey')

    Returns whether the item should be consumed, so the caller knows whether to remove it.
]]
exports('UseItem', function(src, key)
    return Items.use(tonumber(src), key)
end)

--- Which items are configured, and what each does. For a shop or a documentation command.
exports('GetItems', function()
    local out = {}
    for key, entry in pairs(Config.Items) do
        if type(entry) == 'table' and entry.item ~= '' then
            out[key] = {
                item = entry.item,
                effect = entry.effect,
                amount = entry.amount,
                duration = entry.duration,
                cooldown = entry.cooldown,
                label = entry.label,
                description = entry.description,
                weight = entry.weight,
                image = entry.image,
            }
        end
    end
    return out
end)

-- ---------------------------------------------------------------------------------------
-- /vsportitems - the paste-ready blocks, generated from the config
-- ---------------------------------------------------------------------------------------
--
-- Registering these items is the one installation step this resource CANNOT do for itself: every
-- inventory keeps its item list somewhere different, and two of them keep it in a file that an
-- update overwrites.
--
-- What it can do is stop the block being something you transcribe by hand out of a README. This
-- generates it from Config.Items, so renaming `whey` to `proteine` or changing a weight means
-- running the command again rather than editing a file and then remembering which one.

--- Escape a single-quoted Lua string. A description with an apostrophe in it would otherwise
--- produce a block that does not parse, which is a poor first impression for an install step.
local function luaQuote(text)
    return tostring(text or ''):gsub('\\', '\\\\'):gsub("'", "\\'")
end

--- Ordered, so the generated block does not reshuffle itself between runs. `pairs` makes no
--- promises, and a block that changes order every time is one nobody can diff.
local function itemsInOrder()
    local keys = {}
    for key, entry in pairs(Config.Items) do
        if type(entry) == 'table' and entry.item and entry.item ~= '' then
            keys[#keys + 1] = key
        end
    end
    table.sort(keys)
    return keys
end

local BLOCKS = {}

--- What an item is, as far as a catalogue is concerned, read from what it restores. An item
--- that quenches is a drink, one that feeds is food, anything else is just a thing.
local function shelfOf(entry)
    local needs = entry.needs
    if type(needs) == 'table' then
        if (tonumber(needs.thirst) or 0) > 0 then return 'drinks', 'drink' end
        if (tonumber(needs.hunger) or 0) > 0 then return 'food', 'food' end
    end
    return 'misc', 'misc'
end

BLOCKS['v-inventory'] = function(lines)
    lines[#lines + 1] = '-- v-inventory:  v-inventory/data/items.lua'
    lines[#lines + 1] = '-- Paste inside the InventoryItems table, then restart. The catalogue is'
    lines[#lines + 1] = '-- seeded once and owned by the admin panel afterwards, so a row that is'
    lines[#lines + 1] = '-- already in the database keeps the values it has: edit those in the panel.'
    lines[#lines + 1] = '--'
    lines[#lines + 1] = '-- `usable` stays 1 and the type is only the fallback: v-sport registers the'
    lines[#lines + 1] = '-- real effect at boot and claims the item, so the type effect never runs.'
    lines[#lines + 1] = '-- It still decides which shelf the item sits on, and what it is worth as'
    lines[#lines + 1] = '-- food or drink comes from the `needs` table in this module\'s own config.'
    lines[#lines + 1] = ''

    for _, key in ipairs(itemsInOrder()) do
        local it = Config.Items[key]
        local category, itype = shelfOf(it)
        lines[#lines + 1] = ("  { name='%s', label='%s', weight=%d, stackable=1, usable=1, "
            .. "category='%s', image=nil, itype='%s', rarity='common', desc='%s' },")
            :format(it.item, luaQuote(it.label or it.item),
                math.floor(tonumber(it.weight) or 200), category, itype,
                luaQuote(it.description))
    end
end

BLOCKS['qb-core'] = function(lines)
    lines[#lines + 1] = '-- qb-core / qbx_core:  qb-core/shared/items.lua'
    lines[#lines + 1] = '-- Paste inside the QBShared.Items table.'
    lines[#lines + 1] = ''

    for _, key in ipairs(itemsInOrder()) do
        local it = Config.Items[key]
        lines[#lines + 1] = ("    ['%s'] = { name = '%s', label = '%s', weight = %d, "
            .. "type = 'item', image = '%s', unique = false, useable = true, "
            .. "shouldClose = true, combinable = nil, description = '%s' },")
            :format(it.item, it.item, luaQuote(it.label or it.item),
                math.floor(tonumber(it.weight) or 200), it.image or (it.item .. '.png'),
                luaQuote(it.description))
    end
end

BLOCKS['ox_inventory'] = function(lines)
    lines[#lines + 1] = '-- ox_inventory:  ox_inventory/data/items.lua'
    lines[#lines + 1] = '-- Paste inside the return table. No `useable` field: ox decides from'
    lines[#lines + 1] = '-- whether a resource registered a handler, which v-sport does at boot.'
    lines[#lines + 1] = ''

    for _, key in ipairs(itemsInOrder()) do
        local it = Config.Items[key]
        lines[#lines + 1] = ("    ['%s'] = {"):format(it.item)
        lines[#lines + 1] = ("        label = '%s',"):format(luaQuote(it.label or it.item))
        lines[#lines + 1] = ('        weight = %d,'):format(math.floor(tonumber(it.weight) or 200))
        lines[#lines + 1] = '        stack = true,'
        lines[#lines + 1] = '        close = true,'
        lines[#lines + 1] = ("        description = '%s',"):format(luaQuote(it.description))
        lines[#lines + 1] = '        client = { export = nil },'
        lines[#lines + 1] = '    },'
    end
end

BLOCKS['esx'] = function(lines)
    lines[#lines + 1] = '-- ESX (es_extended): items live in the DATABASE, not in a file.'
    lines[#lines + 1] = '-- Run this SQL once. `limit` of -1 means no per-item stack limit.'
    lines[#lines + 1] = ''
    lines[#lines + 1] = 'INSERT INTO items (name, label, weight, rare, can_remove) VALUES'

    local rows = {}
    for _, key in ipairs(itemsInOrder()) do
        local it = Config.Items[key]
        -- ESX weight is in whole units rather than grams, so a 500 g tub is not 500 units.
        local weight = math.max(1, math.floor((tonumber(it.weight) or 200) / 100))
        rows[#rows + 1] = ("    ('%s', '%s', %d, 0, 1)")
            :format(it.item, luaQuote(it.label or it.item), weight)
    end

    lines[#lines + 1] = table.concat(rows, ',\n')
    lines[#lines + 1] = 'ON DUPLICATE KEY UPDATE label = VALUES(label), weight = VALUES(weight);'
end

--[[
    Print the block for one inventory, or for the one this server is running.

    Defaults to what was detected rather than printing all three, because the common case is an
    operator who wants the answer and not a menu. `all` prints everything, for someone writing
    documentation or migrating between inventories.
]]
--[[
    Which inventory this server actually runs, in the same order registration uses.

    v-inventory first: it is the framework's own inventory and the one this module registers
    against. Without it the fall-through handed a v-core server the qb-core block, which does
    nothing here and reads as if the item had been added.
]]
local function detectInventory()
    if GetResourceState('v-inventory') == 'started' then return 'v-inventory' end
    -- ox_inventory next, because a server can run it ON TOP of qb-core, in which case ox owns
    -- the item list.
    if GetResourceState('ox_inventory') == 'started' then return 'ox_inventory' end
    -- Bridge.framework() answers the RESOURCE name, which for ESX is 'es_extended' - so a
    -- search for 'esx' never matched and an ESX server was handed the qb-core block.
    if Bridge.framework():find('es_extended') or Bridge.framework():find('esx') then
        return 'esx'
    end
    return 'qb-core'
end

local function printItems(target, which)
    local lines = {}

    -- `which` reaches here from a net event, so it is whatever the caller chose to send and not
    -- necessarily one of the names below. It is only ever compared against BLOCKS, except in the
    -- unknown-inventory line, which puts it in the console verbatim. Capped and flattened here,
    -- once, for every path: without a length limit one call prints a string of any size, and a
    -- newline inside it turns that one line into several that can be dressed up as another
    -- resource's log in front of whoever is reading the console.
    which = tostring(which or ''):lower():gsub('%c', ' '):sub(1, 40)

    if which == '' then
        which = detectInventory()
        lines[#lines + 1] = ('-- Detected: %s. Pass a name to this command for another one:'):format(which)
        lines[#lines + 1] = '--   v-inventory | qb-core | ox_inventory | esx | all'
        lines[#lines + 1] = ''
    end

    if which == 'all' then
        for _, name in ipairs({ 'v-inventory', 'qb-core', 'ox_inventory', 'esx' }) do
            BLOCKS[name](lines)
            lines[#lines + 1] = ''
        end
    elseif BLOCKS[which] then
        BLOCKS[which](lines)
    else
        lines[#lines + 1] = ('unknown inventory "%s". Known: v-inventory, qb-core, ox_inventory, esx, all')
            :format(which)
    end

    lines[#lines + 1] = ''
    lines[#lines + 1] = '-- Images: put images/*.png into your inventory\'s image folder.'
    lines[#lines + 1] = '-- v-sport ships SVG sources in images/ - see images/README.md.'

    print('^5==== v-sport: add these items to your inventory ====^7')
    for _, line in ipairs(lines) do print(line) end
    print('^5===================================================^7')

    if target and target ~= 0 then
        TriggerClientEvent('vsport:client:ItemBlocks', target, lines)
    end
end

--- The block for one inventory, as a list of lines. No argument, or an empty one, answers for
--- the inventory this server actually runs rather than assuming qb-core.
exports('GetItemBlocks', function(which)
    local lines = {}
    local key = tostring(which or ''):lower()
    if key == '' then key = detectInventory() end
    if BLOCKS[key] then BLOCKS[key](lines) end
    return lines
end)

RegisterNetEvent('vsport:server:ItemBlocks', function(which)
    local src = source
    if Config.Commands.restrictDevCommands ~= false and not Bridge.isAdmin(src) then
        Bridge.notify(src, L('notify.no_permission'), 'error')
        return
    end
    printItems(src, which)
end)

CreateThread(function()
    local name = Config.Commands.items
    if type(name) ~= 'string' or name == '' then return end

    Bridge.addCommand(name, L('cmd.items'), {
        { name = 'inventory', help = 'qb-core | ox_inventory | esx | all' },
    }, true, function(src, rawArgs)
        local args = rawArgs
        if type(args) == 'string' then
            args = {}
            for word in rawArgs:gmatch('%S+') do args[#args + 1] = word end
        end
        printItems(src, type(args) == 'table' and args[1] or nil)
    end)
end)
