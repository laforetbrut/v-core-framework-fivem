-- v-gathering | server
-- Authority: the client asks to harvest a node index; the server confirms the player
-- is really at that node, enforces a cooldown, rolls the yield and grants it.
local Core = exports['v-core']:GetCore()

local Busy   = {}   -- src -> true while a harvest resolves
local LastAt = {}   -- src -> os.time() of last harvest

-- Weighted pick over a resource's yields -> { item, amount }.
local function rollYield(res)
    local total = 0
    for _, y in ipairs(res.yields) do total = total + (y.weight or 1) end
    if total <= 0 then return nil end
    local pick = math.random() * total
    local acc = 0
    for _, y in ipairs(res.yields) do
        acc = acc + (y.weight or 1)
        if pick <= acc then
            local amount = math.random(y.min or 1, math.max(y.min or 1, y.max or 1))
            return { item = y.item, amount = amount }
        end
    end
    local y = res.yields[#res.yields]
    return { item = y.item, amount = y.min or 1 }
end

-- Is `source` actually standing at node #idx, and is its type as claimed?
local function atNode(source, idx, resType)
    local node = Config.Nodes[idx]
    if not node or node.type ~= resType then return nil end
    local res = Config.Resources[node.type]
    if not res then return nil end
    local ped = GetPlayerPed(source)
    if not ped or ped == 0 then return nil end
    if #(GetEntityCoords(ped) - node.coords) > (Config.Distance + 1.6) then return nil end
    return res
end

Core.RegisterCallback('v-gathering:harvest', function(source, resolve, data)
    data = data or {}
    local idx = tonumber(data.idx)
    local resType = data.type

    if Busy[source] then resolve({ error = 'busy' }); return end
    local res = atNode(source, idx, resType)
    if not res then resolve({ error = 'far' }); return end
    -- Gate on the resource's OWN harvest duration (ms, server-authoritative) — not just a
    -- flat cooldown. The animation that paces legit players is client-side, so a scripted
    -- client firing the callback directly must still be throttled to res.time here.
    local now = GetGameTimer()
    local minGap = math.max(res.time or 4000, (Config.Cooldown or 2) * 1000)
    if now - (LastAt[source] or 0) < minGap then resolve({ error = 'cooldown' }); return end

    Busy[source] = true

    local roll = rollYield(res)
    if not roll then Busy[source] = nil; resolve(false); return end

    -- Grant the main yield; the rare bonus only if it also fits.
    if not exports['v-inventory']:AddItem(source, roll.item, roll.amount) then
        Busy[source] = nil
        Core.Notify(source, LP(source, 'gather.full'), 'error'); resolve({ error = 'space' }); return
    end

    local bonus
    if res.rare and math.random() < (res.rare.chance or 0) then
        if exports['v-inventory']:AddItem(source, res.rare.item, 1) then bonus = res.rare.item end
    end

    LastAt[source] = now
    Busy[source] = nil

    local player = Core.GetPlayer(source)
    Core.Log('gathering', ('%s harvested %dx %s%s'):format(
        player and player.citizenid or source, roll.amount, roll.item,
        bonus and (' (+'..bonus..')') or ''), nil, player and player.citizenid or nil)

    resolve({ ok = true, item = roll.item, amount = roll.amount, bonus = bonus })
end)

AddEventHandler('playerDropped', function()
    local src = source
    Busy[src] = nil; LastAt[src] = nil
end)
