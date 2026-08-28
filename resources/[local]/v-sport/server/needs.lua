--[[
    v-sport | server/needs.lua

    A finished set costs the body something. Sport owns strength, breath and stamina; hunger,
    thirst and stress belong to the server's needs resource (v-status here), so this asks that
    resource for the change rather than keeping a second set of numbers that would drift.

    It hangs off `vsport:server:SessionCompleted`, the event stats.lua already fires, so
    nothing in the training path had to change to make room for it. That event only fires for
    a set that actually paid, which is the wanted behaviour: a session refused by the rate
    limit or the allowance never happened as far as the body is concerned.

    Inert by design. With Config.Needs.enabled off, or with no provider running, every branch
    below returns before it asks anything of anybody.
]]

local provider          -- resource name of the needs owner, resolved once
local resolved = false

--- The first configured needs resource that is actually running. Resolved lazily rather than
--- at start-up, because this file can load before the needs resource does.
local function findProvider()
    if resolved then return provider end

    for _, name in ipairs(Config.Needs.providers or {}) do
        if GetResourceState(name) == 'started' then
            provider = name
            resolved = true
            Sport.debug(('needs: using %s'):format(name))
            return provider
        end
    end

    -- Not resolved: a provider that starts later is picked up on the next session.
    return nil
end

--- The player's current value for `key`, or nil when the provider cannot say.
local function currentValue(name, src, key)
    local ok, status = pcall(function() return exports[name]:Get(src) end)
    if not ok or type(status) ~= 'table' then return nil end
    return tonumber(status[key])
end

-- The floor guards the "how full" needs only. Stress reads the other way round - 0 is a calm
-- character, which is exactly where a workout is supposed to push it - so a floor there would
-- stop the relief at an arbitrary number.
local FLOORED = { hunger = true, thirst = true }

--- Apply one need change, holding a fullness need above the configured floor.
local function charge(name, src, key, delta)
    if delta == 0 then return end

    local floor = FLOORED[key] and tonumber(Config.Needs.floor) or nil

    -- The floor only ever holds a value UP, so it applies to a change that takes one down.
    if floor and delta < 0 then
        local current = currentValue(name, src, key)
        if current then
            if current <= floor then return end
            -- Never step past the floor, however large the configured cost is.
            delta = math.max(delta, floor - current)
        end
    end

    local ok = pcall(function() exports[name]:Add(src, key, delta) end)
    if not ok then
        Sport.warn(('needs: %s did not accept an Add(%s) - the cost was skipped.')
            :format(name, key))
    end
end

local NEEDS = { 'hunger', 'thirst', 'stress' }

--- Apply a { hunger =, thirst =, stress = } table, each value multiplied by `scale`.
local function applyNeeds(name, src, amounts, scale)
    for _, need in ipairs(NEEDS) do
        local amount = tonumber(amounts[need]) or 0
        if amount ~= 0 then
            charge(name, src, need, amount * scale)
        end
    end
end

AddEventHandler('vsport:server:SessionCompleted', function(src, key, gains, quality)
    if not Config.Needs.enabled then return end

    local name = findProvider()
    if not name then return end

    -- The same 0..1 the gains were paid on, so half a set costs half as much.
    local scale = 1.0
    if Config.Needs.scaleWithQuality then
        scale = Sport.clamp(quality, 0.0, 1.0, 1.0)
        if scale <= 0 then return end
    end

    applyNeeds(name, src, Config.Needs, scale)

    Sport.debug(('needs: charged %s for %s at %.2f'):format(
        GetPlayerName(src) or src, tostring(key), scale))
end)

--[[
    What a supplement is worth as food and drink.

    A protein bar is still a bar and a sports drink is still a drink, but the inventory hands
    a claimed item entirely to its owner: the moment v-sport registered a handler for these
    four, their plain food and drink value went with it. This gives it back, from each item's
    own `needs` table in section 5c, so one item is described in one place.

    Only fires for a use that actually took effect - v-sport raises this after the effect, not
    before - so a supplement refused on a cooldown feeds nobody, and now keeps its item too.
]]
AddEventHandler('vsport:server:ItemUsed', function(src, key)
    if not (Config.Needs.enabled and Config.Needs.itemNutrition) then return end

    local entry = Config.Items[key]
    local amounts = entry and entry.needs
    if type(amounts) ~= 'table' then return end

    local name = findProvider()
    if not name then return end

    applyNeeds(name, src, amounts, 1.0)
    Sport.debug(('needs: %s ate or drank %s'):format(GetPlayerName(src) or src, tostring(key)))
end)
