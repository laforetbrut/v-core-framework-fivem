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
