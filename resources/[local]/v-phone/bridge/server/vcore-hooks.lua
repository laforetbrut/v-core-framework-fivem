-- v-phone | bridge/server/vcore-hooks.lua
--
-- **What this framework answers, through the seam the resource already offers.**
--
-- The bridge detects qb-core, ox_core and ESX, and falls back to `standalone` when it finds
-- none of them. On v-core it finds none of them, which is correct - v-core is not one of those
-- - and the phone said so plainly the moment it was asked:
--
--     [v-phone] framework: standalone
--     [v-phone] bridge apps: garage=no property=no licences=no jobs=no
--
-- Every `Bridge.*` reader opens by consulting `Config.Compat.hooks`, which config.lua documents
-- as the operator's own way in, with the shape each one has to return. That is the seam, so
-- nothing in the bridge is edited: the hooks are filled from v-core's own modules and the
-- detection below them is left exactly as it is. A server that later runs qb-core alongside
-- would keep working, because a hook that finds nothing returns nil and the bridge carries on
-- to its own detection.

local function ready(resource)
    return GetResourceState(resource) == 'started'
end

--- Ask an export without letting a missing one take the caller down.
local function ask(resource, method, ...)
    if not ready(resource) then return nil end
    local ok, result = pcall(function(...) return exports[resource][method](exports[resource], ...) end, ...)
    if not ok then return nil end
    return result
end

Config.Compat = Config.Compat or {}
Config.Compat.hooks = Config.Compat.hooks or {}

--[[
    The job list, for the Jobs app.

    Read from v-world rather than from `v-cityhall:OpenPositions()`, which is the other
    candidate and the wrong one: it keeps only the FIRST grade of each job, because it answers
    "what is hiring", and the Jobs app draws the whole ladder. v-world holds the rows the
    editor writes, `grades` being a map of level -> { name, salary }.

    Shape required, from config.lua: () -> { { name, label, grades }, ... }, each grade
    { grade, label, salary }. `pay` is emitted beside `salary` because the bridge's own qb
    branch does, and an operator's code may have come to read either.
]]
Config.Compat.hooks.jobs = function()
    local rows = ask('v-world', 'GetJobs')
    if type(rows) ~= 'table' then return nil end

    local out = {}
    for _, job in ipairs(rows) do
        if type(job) == 'table' and job.name then
            local grades = {}
            for level, g in pairs(job.grades or {}) do
                local wage = tonumber(g and g.salary) or 0
                grades[#grades + 1] = {
                    grade = tonumber(level) or 0,
                    label = (g and g.name) or '',
                    salary = wage,
                    pay = wage,
                }
            end
            -- `pairs` over a level-keyed map has no order; the app draws a ladder.
            table.sort(grades, function(a, b) return a.grade < b.grade end)
            out[#out + 1] = {
                name = job.name,
                label = job.label or job.name,
                grades = grades,
            }
        end
    end
    if #out == 0 then return nil end

    table.sort(out, function(a, b) return (a.label or '') < (b.label or '') end)
    return out
end

--[[
    Owned vehicles, for the Garage app.

    `v-vehicles:GetOwned` takes a SOURCE, which is not what this hook is handed; the module
    publishes `GetOwnedByCid` beside it for exactly this. Its rows come straight out of
    character_vehicles, so plate, model, garage and state are already the names the hook
    asks for and nothing is renamed on the way through.

    Shape required: (citizenid) -> { { plate, model, garage, state }, ... }
]]
Config.Compat.hooks.vehicles = function(citizenid)
    local rows = ask('v-vehicles', 'GetOwnedByCid', tostring(citizenid or ''))
    if type(rows) ~= 'table' then return nil end

    local out = {}
    for _, r in ipairs(rows) do
        if type(r) == 'table' and r.plate then
            out[#out + 1] = {
                plate = tostring(r.plate),
                model = tostring(r.model or ''),
                garage = tostring(r.garage or ''),
                state = r.state,
            }
        end
    end
    -- An empty table, not nil: the module answered and this character owns nothing, which
    -- is a different thing from having no provider at all.
    return out
end

--[[
    Licences held, for the Wallet app.

    Two sources, because neither has both halves. v-licenses knows WHICH a character holds
    and their status; the label lives in v-world's `license_types` rows, where the editor
    writes it. v-licenses' own Config.Types carries `i18n = 'lic.driving'` rather than a
    label, and handing the phone a translation key would put `lic.driving` on the card.

    Only `valid` is passed through. The shape has no room for a status, so a revoked or
    suspended licence listed here would read as one the character still holds - which is
    the opposite of what those statuses mean. `HasByCid` draws the same line.

    Shape required: (src, citizenid) -> { { type, label }, ... }
]]
Config.Compat.hooks.licences = function(_, citizenid)
    local rows = ask('v-licenses', 'GetAllByCid', tostring(citizenid or ''))
    if type(rows) ~= 'table' then return nil end

    local labels = {}
    for _, ty in ipairs(ask('v-world', 'GetLicenseTypes') or {}) do
        if type(ty) == 'table' and ty.key then labels[tostring(ty.key)] = ty.label end
    end

    local out = {}
    for _, r in ipairs(rows) do
        if type(r) == 'table' and r.type and r.status == 'valid' then
            local key = tostring(r.type)
            out[#out + 1] = { type = key, label = labels[key] or key }
        end
    end
    return out
end

--[[
    Properties held, for the Property app.

    v-housing's `GetProperties` is the map catalogue and takes no argument, so it answers
    what exists rather than what a character owns - which is why the bridge's own
    registration reached for a `GetOwned` that was never there. `OwnedByCid` is the reader
    for this, and it lives in v-housing because ownership, tenancy and arrears are that
    module's to define.

    Shape required: (citizenid) -> { { label, address }, ... }
    `address` is the property id, which is what this framework calls a place; the label is
    already resolved against the catalogue on the way out of v-housing.
]]
Config.Compat.hooks.properties = function(citizenid)
    local rows = ask('v-housing', 'OwnedByCid', tostring(citizenid or ''))
    if type(rows) ~= 'table' then return nil end

    local out = {}
    for _, r in ipairs(rows) do
        if type(r) == 'table' and r.property then
            out[#out + 1] = {
                label = tostring(r.label or r.property),
                address = tostring(r.property),
            }
        end
    end
    return out
end

-- ══════════════════════════════════════════════════════════════
-- Money
-- ══════════════════════════════════════════════════════════════
--[[
    Without these the bridge reaches its last line - "Standalone, or a framework with no
    money to take. Refuse rather than give it away" - and returns false. That is the right
    failure and it is why nothing was ever charged wrongly, but it also means the store, the
    transfers, Bank Pro and the donation pages all refuse on this framework.

    v-core's player object is the whole answer: AddMoney and RemoveMoney each run the
    framework's own hook, floor the amount, and RemoveMoney refuses when the balance is
    short. They return true only when the money actually moved, which is the exact contract
    config.lua asks for here - the store treats false as "not paid" and grants nothing, and
    a transfer whose credit reports false is refunded to the sender rather than lost.

    Its accounts are named `cash` and `bank`, which are the two names the phone passes.
]]
local core
local function player(src)
    if not core then core = ask('v-core', 'GetCore') end
    if type(core) ~= 'table' or not core.GetPlayer then return nil end
    local ok, p = pcall(core.GetPlayer, tonumber(src))
    return ok and p or nil
end

--- (src) -> { cash, bank }
Config.Compat.hooks.balances = function(src)
    local p = player(src)
    if not p or not p.GetMoney then return nil end
    return {
        cash = math.floor(tonumber(p.GetMoney('cash')) or 0),
        bank = math.floor(tonumber(p.GetMoney('bank')) or 0),
    }
end

--- (src, amount, account) -> boolean. True ONLY when the money left them.
Config.Compat.hooks.removeMoney = function(src, amount, account)
    local p = player(src)
    if not p or not p.RemoveMoney then return false end
    return p.RemoveMoney((account == 'cash') and 'cash' or 'bank',
                         math.floor(tonumber(amount) or 0), 'v-phone') == true
end

--- (src, amount, account, reason) -> boolean. True ONLY when the money arrived.
Config.Compat.hooks.addMoney = function(src, amount, account, reason)
    local p = player(src)
    if not p or not p.AddMoney then return false end
    return p.AddMoney((account == 'cash') and 'cash' or 'bank',
                      math.floor(tonumber(amount) or 0),
                      tostring(reason or 'v-phone')) == true
end

--[[
    Needs, for the Health app.

    Without this the bridge checks for esx_status, then branches on qb and ox, and falls
    off the end returning nil - which the app draws as zeros. The preview showed exactly
    that: 0 hunger, 0 thirst, 0 stress on a character who had none of those things wrong.

    v-status owns them and says so in its own header: hunger, thirst and stress are its,
    while health and armour stay native and are read off the ped by the client. So only the
    three it actually keeps are passed, and the app reads the other two where it always did.

    Shape required: (src) -> { hunger, thirst, ... }
]]
Config.Compat.hooks.status = function(src)
    local s = ask('v-status', 'Get', tonumber(src))
    if type(s) ~= 'table' then return nil end
    return {
        hunger = tonumber(s.hunger),
        thirst = tonumber(s.thirst),
        stress = tonumber(s.stress),
    }
end

--[[
    Who the character is, for the Wallet's identity card.

    Read from the `characters` table rather than from a player object, because this is
    asked by CITIZEN ID and not by source: the Wallet draws a card for somebody who may not
    be connected, and an export on the player object cannot answer for one who is not.
    Reading the framework's own character table is what the qb, ox and ESX branches of this
    same function already do - `players`, `characters` and `users` respectively - so this
    follows the shape the file established rather than inventing one.

    `sex` is a tinyint here, 0 and 1, which is the convention the bridge's own sexOf()
    normalises: 0 male, 1 female. It is normalised on this side too so the card is handed
    the same 'm'/'f' every other branch produces. There is no nationality column, and the
    field is left out rather than filled with a guess.

    Shape required: (citizenid, src) -> { first, last, dob, sex, id }
]]
Config.Compat.hooks.identity = function(citizenid, _)
    citizenid = tostring(citizenid or '')
    if citizenid == '' then return nil end

    local row = MySQL.single.await(
        'SELECT firstname, lastname, dob, sex FROM characters WHERE citizenid = ?',
        { citizenid })
    if type(row) ~= 'table' then return nil end

    local sex
    local n = tonumber(row.sex)
    if n == 0 then sex = 'm' elseif n == 1 then sex = 'f' end

    return {
        first = row.firstname,
        last = row.lastname,
        dob = row.dob,
        sex = sex,
        id = citizenid,
    }
end

--[[
    What a vehicle is CALLED, from its spawn code.

    The Garage app draws the `model` it is handed, and without this the bridge's last line
    capitalises the spawn code: `brioso` becomes `Brioso`, `adder` becomes `Adder`. The
    catalogue in this framework has the real names - adder is a Truffade Adder - so a player
    reads a car's name rather than its asset name.

    Read from v-world rather than from `v-vehicleshop:GetCatalogue()`, which is the
    dealership's view and answers what is FOR SALE. A label is needed for every car anybody
    owns, including one the dealers stopped stocking, and v-world holds the rows the editor
    writes. Same reason the job list is read from there.

    Cached, because a garage list asks this once per vehicle and the table is a hundred
    rows of nothing changing. `v-world:server:changed` is the framework's own signal that
    an editor wrote something, and it is what v-vehicleshop rebuilds on, so the cache is
    dropped there rather than left to go stale until a restart.
]]
local labels

AddEventHandler('v-world:server:changed', function(domain)
    if domain == nil or domain == 'vehcat' then labels = nil end
end)

Config.Compat.hooks.vehicleLabel = function(model)
    model = tostring(model or ''):lower()
    if model == '' then return nil end

    if not labels then
        local rows = ask('v-world', 'GetVehicleCatalogue')
        if type(rows) ~= 'table' then return nil end
        labels = {}
        for _, r in ipairs(rows) do
            if type(r) == 'table' and r.model and r.label then
                labels[tostring(r.model):lower()] = tostring(r.label)
            end
        end
    end

    -- nil, not the model: the bridge's own fallback capitalises it, and answering with the
    -- spawn code here would replace that with the same thing while claiming it is a name.
    local label = labels[model]
    if type(label) ~= 'string' or label == '' then return nil end
    return label
end
