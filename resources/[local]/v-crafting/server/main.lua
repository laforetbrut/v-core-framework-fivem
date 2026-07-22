-- v-crafting | server
-- Authority: validates the player is really at the requested bench, owns the
-- inputs, and has space for the output before consuming anything.
local Core = exports['v-core']:GetCore()

local ItemDefs = {}   -- name -> row (label / image / weight / category / rarity)
local Busy     = {}   -- src -> true while a craft is resolving (anti double-submit)
local LastAt   = {}   -- src -> os.time() of last craft (cooldown)

-- Live recipe list. Sourced from the DB via v-world (admin-editable in-game); falls
-- back to Config.Recipes when v-world is absent, so a fresh install is unchanged.
local Recipes = Config.Recipes

local function loadItemDefs()
    ItemDefs = {}
    for _, r in ipairs(MySQL.query.await('SELECT name, label, image, weight, category, metadata FROM items') or {}) do
        ItemDefs[r.name] = r
    end
end

local function rebuildRecipes()
    if GetResourceState('v-world') ~= 'started' then Recipes = Config.Recipes; return end
    local ok, rows = pcall(function() return exports['v-world']:GetRecipes() end)
    if not ok or type(rows) ~= 'table' or #rows == 0 then Recipes = Config.Recipes; return end
    local out = {}
    for _, r in ipairs(rows) do
        if r.enabled == 1 or r.enabled == true then
            out[#out + 1] = { station = r.station, output = r.output, count = r.count or 1,
                              time = r.time or 3000, inputs = r.inputs or {} }
        end
    end
    Recipes = out
end

CreateThread(function()
    while GetResourceState('oxmysql') ~= 'started' do Wait(100) end
    loadItemDefs()

    -- Hand our static recipes to v-world once (it seeds only when empty), then follow
    -- the DB so admins can create/edit recipes from the panel.
    if GetResourceState('v-world') ~= 'missing' then
        local t = 0
        while GetResourceState('v-world') ~= 'started' and t < 100 do Wait(100); t = t + 1 end
        if GetResourceState('v-world') == 'started' then
            t = 0
            while not (pcall(function() return exports['v-world']:IsReady() end) and exports['v-world']:IsReady()) and t < 100 do
                Wait(100); t = t + 1
            end
            pcall(function() exports['v-world']:SeedRecipes(Config.Recipes) end)
            rebuildRecipes()
        end
    end
end)

-- Admin edited items or recipes in the panel -> apply immediately.
AddEventHandler('v-world:server:changed', function(domain)
    if domain == nil or domain == 'items' then loadItemDefs() end
    if domain == nil or domain == 'recipes' then rebuildRecipes() end
end)

local function defOf(name)
    local d = ItemDefs[name]
    if not d then return { label = name, image = nil, category = 'misc', rarity = 'common' } end
    local meta = d.metadata
    if type(meta) == 'string' then meta = json.decode(meta) or {} end
    return { label = d.label, image = d.image, weight = d.weight, category = d.category,
             rarity = (meta and meta.rarity) or 'common' }
end

-- One pass over the inventory -> a name->count map (avoids an export round-trip per
-- ingredient per recipe when building a station's list).
local function countsOf(source)
    local counts = {}
    for _, it in ipairs(exports['v-inventory']:GetItems(source) or {}) do
        counts[it.name] = (counts[it.name] or 0) + (it.amount or 0)
    end
    return counts
end

-- Recipes for a station, resolved with defs + the player's current input counts.
local function recipesFor(source, stationId)
    local counts = countsOf(source)
    local out = {}
    for i, r in ipairs(Recipes) do
        if r.station == stationId then
            local inputs = {}
            for item, qty in pairs(r.inputs) do
                local d = defOf(item)
                inputs[#inputs + 1] = { item = item, need = qty, label = d.label,
                    image = d.image, have = counts[item] or 0 }
            end
            table.sort(inputs, function(a, b) return a.item < b.item end)
            local d = defOf(r.output)
            out[#out + 1] = { idx = i, output = r.output, label = d.label, image = d.image,
                category = d.category, rarity = d.rarity, count = r.count,
                -- the client's progress bar is driven by this, so the multiplier has to be
                -- applied where the recipe is SENT, not only where the cooldown is derived
                time = math.max(200, math.floor((r.time or 3000) * (Config.TimeMult or 1.0))),
                inputs = inputs }
        end
    end
    return out
end

-- Is `source` actually standing at one of the station's benches?
local function atBench(source, stationId)
    local st = Config.Stations[stationId]
    if not st then return false end
    local ped = GetPlayerPed(source)
    if not ped or ped == 0 then return false end
    local pos = GetEntityCoords(ped)
    for _, b in ipairs(st.benches) do
        if #(pos - vector3(b.x, b.y, b.z)) <= (Config.Distance + 1.5) then return true end
    end
    return false
end

local function canGate(source, gate)
    if not gate then return true end
    if gate.permission and not Core.HasPermission(source, gate.permission) then return false end
    if gate.job then
        local player = Core.GetPlayer(source)
        local job = player and player.job
        if not job or job.name ~= gate.job then return false end
        if gate.grade and (job.grade or 0) < gate.grade then return false end
    end
    return true
end

Core.RegisterCallback('v-crafting:getStation', function(source, resolve, stationId)
    local st = Config.Stations[stationId]
    if not st or not atBench(source, stationId) then resolve(false); return end
    resolve({ id = stationId, label = st.label, recipes = recipesFor(source, stationId) })
end)

Core.RegisterCallback('v-crafting:craft', function(source, resolve, data)
    data = data or {}
    local stationId = data.station
    local recipe = Recipes[tonumber(data.idx) or -1]
    local amount = math.max(1, math.min(10, math.floor(tonumber(data.amount) or 1)))

    if Busy[source] then resolve({ error = 'busy' }); return end
    if not recipe or recipe.station ~= stationId then resolve(false); return end
    if not atBench(source, stationId) then
        Core.Notify(source, LP(source, 'craft.too_far'), 'error'); resolve({ error = 'far' }); return
    end
    if not canGate(source, recipe.gate) then
        Core.Notify(source, LP(source, 'craft.locked'), 'error'); resolve({ error = 'gate' }); return
    end
    -- Enforce the recipe's OWN craft time server-side (the progress bar is client-side
    -- and bypassable) plus the flat floor, so a scripted client can't craft instantly.
    local minGap = math.max(Config.Cooldown or 1,
        math.ceil(((recipe.time or 0) * (Config.TimeMult or 1.0)) / 1000))
    if os.time() - (LastAt[source] or 0) < minGap then resolve({ error = 'cooldown' }); return end

    Busy[source] = true

    -- Verify every input is present for the requested amount before touching anything.
    for item, qty in pairs(recipe.inputs) do
        if (exports['v-inventory']:GetItemCount(source, item) or 0) < qty * amount then
            Busy[source] = nil
            Core.Notify(source, LP(source, 'craft.missing'), 'error'); resolve({ error = 'missing' }); return
        end
    end

    -- Consume inputs, then add the output. If the output can't fit, refund the inputs.
    local removed = {}
    for item, qty in pairs(recipe.inputs) do
        exports['v-inventory']:RemoveItem(source, item, qty * amount)
        removed[item] = qty * amount
    end

    if not exports['v-inventory']:AddItem(source, recipe.output, recipe.count * amount) then
        for item, qty in pairs(removed) do exports['v-inventory']:AddItem(source, item, qty) end
        Busy[source] = nil
        Core.Notify(source, LP(source, 'craft.nospace'), 'error'); resolve({ error = 'space' }); return
    end

    LastAt[source] = os.time()
    Busy[source] = nil

    local player = Core.GetPlayer(source)
    Core.Log('crafting', ('%s crafted %dx %s'):format(
        player and player.citizenid or source, recipe.count * amount, recipe.output), nil,
        player and player.citizenid or nil)
    Core.Notify(source, LP(source, 'craft.done', recipe.count * amount, defOf(recipe.output).label), 'success')

    -- Return the refreshed recipe list so the panel updates owned counts live.
    resolve({ ok = true, recipes = recipesFor(source, stationId) })
end)

AddEventHandler('playerDropped', function()
    local src = source
    Busy[src] = nil; LastAt[src] = nil
end)

-- ══════════════════════════════════════════════════════════════════
--  Admin-tunable settings (v-core module registry)
-- ══════════════════════════════════════════════════════════════════
-- Declared to v-core, which stores the values and serves them to the admin panel.
-- Applied back onto Config so the existing code paths see an operator's change without
-- a restart. See INTEGRATION.md.
local function declareSettings()
    Core.RegisterModule('v-crafting', {
        label = 'Crafting', category = 'economy',
        settings = {

            { key = 'distance', label = 'Bench range (m)',        type = 'number', default = Config.Distance, min = 0.5, max = 10 },
            { key = 'cooldown', label = 'Craft cooldown (s)',     type = 'number', default = Config.Cooldown, min = 0, max = 60 },
            { key = 'timeMult', label = 'Craft duration multiplier', type = 'number', default = 1.0, min = 0.1, max = 5 },
        },
    })
end

local function S(key, fallback) return Core.GetSetting('v-crafting', key, fallback) end

local function applySettings()

    Config.Distance = S('distance', Config.Distance)
    Config.Cooldown = S('cooldown', Config.Cooldown)
    Config.TimeMult = S('timeMult', 1.0)
end

AddEventHandler('v-core:server:settingChanged', function(mod)
    if mod == 'v-crafting' then applySettings() end
end)

CreateThread(function()
    Wait(2600)          -- let v-core's registry come up first
    declareSettings()
    applySettings()
end)
