-- v-jobs | server
-- Owns jobs/grades/duty/salaries and the exports other modules use to gate access.
local Core = exports['v-core']:GetCore()

local Duty = {}   -- [src] = bool (on/off duty; defaults on when holding a paid job)

-- Live job definitions. Sourced from the DB via v-world (admin-editable in-game);
-- falls back to Config.Jobs when v-world is absent or the table is still empty, so
-- the module behaves exactly as before on a fresh install.
local JobDefs = Config.Jobs

local function jobDef(name) return JobDefs[name] end
local function gradeDef(name, grade)
    local j = JobDefs[name]
    return j and j.grades and j.grades[grade or 0] or nil
end

-- Rebuild JobDefs from v-world rows ({name,label,type,grades=[{grade,name,salary}]})
-- into the Config shape ({label, grades = {[n] = {name, salary}}}) the module uses.
local function rebuildJobs()
    if GetResourceState('v-world') ~= 'started' then JobDefs = Config.Jobs; return end
    local ok, rows = pcall(function() return exports['v-world']:GetJobs() end)
    if not ok or type(rows) ~= 'table' or #rows == 0 then JobDefs = Config.Jobs; return end
    local out = {}
    for _, r in ipairs(rows) do
        local grades = {}
        for _, g in ipairs(r.grades or {}) do
            grades[math.floor(tonumber(g.grade) or 0)] = { name = g.name, salary = tonumber(g.salary) or 0 }
        end
        if next(grades) == nil then grades[0] = { name = 'Employee', salary = 0 } end
        out[r.name] = { label = r.label or r.name, type = r.type, grades = grades }
    end
    JobDefs = out
end

-- Seed the DB from Config on first boot, then follow the DB from there on.
CreateThread(function()
    if GetResourceState('v-world') == 'missing' then return end
    local t = 0
    while GetResourceState('v-world') ~= 'started' and t < 100 do Wait(100); t = t + 1 end
    if GetResourceState('v-world') ~= 'started' then return end
    t = 0
    while not (pcall(function() return exports['v-world']:IsReady() end) and exports['v-world']:IsReady()) and t < 100 do
        Wait(100); t = t + 1
    end
    pcall(function() exports['v-world']:SeedJobs(Config.Jobs) end)
    rebuildJobs()
end)

-- An admin edited jobs in the panel -> pick the change up immediately.
AddEventHandler('v-world:server:changed', function(domain)
    if domain == nil or domain == 'jobs' then rebuildJobs() end
end)

exports('GetJobDefs', function() return JobDefs end)

-- Is `src` on duty? Unset defaults to true so a freshly-assigned job earns right away.
local function isOnDuty(src)
    if Duty[src] == nil then return true end
    return Duty[src] == true
end

-- ── Exports ────────────────────────────────────────────────────
exports('GetJob', function(src)
    local p = Core.GetPlayer(src)
    return p and p.job or nil
end)

-- Assign a job. Validates the job + grade exist in config. Returns bool.
exports('SetJob', function(src, name, grade)
    local p = Core.GetPlayer(src)
    if not p or not jobDef(name) then return false end
    grade = tonumber(grade) or 0
    if not gradeDef(name, grade) then grade = 0 end
    p.SetJob(name, grade)
    Duty[src] = true
    -- Job-gated content (restricted map blips, …) must re-evaluate for this player.
    TriggerEvent('v-jobs:server:changed', src, name, grade)
    return true
end)

exports('IsOnDuty', function(src) return isOnDuty(src) end)
exports('SetDuty',  function(src, on) Duty[src] = on and true or false end)

-- Label helpers for UIs.
exports('GetJobLabel', function(name) local j = jobDef(name); return j and j.label or name end)
exports('GetGradeLabel', function(name, grade) local g = gradeDef(name, grade); return g and g.name or '' end)

-- ── Salary loop ────────────────────────────────────────────────
CreateThread(function()
    while true do
        -- read the interval EVERY loop: it is admin-tunable, and caching it here meant a
        -- change only took effect after a restart
        Wait(math.max(1, (Config.PayInterval or 10)) * 60000)
        local account = Config.PayAccount or 'bank'
        for _, sid in ipairs(GetPlayers()) do
            local src = tonumber(sid)
            local p = src and Core.GetPlayer(src)
            if p and p.job and isOnDuty(src) then
                local g = gradeDef(p.job.name, p.job.grade)
                local pay = math.floor((g and g.salary or 0) * (Config.SalaryMult or 1.0))
                if pay > 0 then
                    p.AddMoney(account, pay, 'salary')
                    Core.Notify(src, LP(src, 'jobs.paid', pay), 'success')
                end
            end
        end
    end
end)

-- ── Admin command: assign a job ────────────────────────────────
-- setjob <playerId> <jobId> [grade]   (admin+ only; console = id 0)
RegisterCommand('setjob', function(source, args)
    if source ~= 0 and not Core.HasPermission(source, 'admin') then return end
    local target = tonumber(args[1])
    local name   = args[2]
    local grade  = tonumber(args[3]) or 0
    if not target or not name or not jobDef(name) then
        if source ~= 0 then Core.Notify(source, LP(source, 'jobs.usage'), 'error') end
        return
    end
    if exports['v-jobs']:SetJob(target, name, grade) then
        if not gradeDef(name, grade) then grade = 0 end   -- mirror SetJob's clamp-to-0 so labels/log are accurate
        local g = gradeDef(name, grade) or {}
        Core.Notify(target, LP(target, 'jobs.set', jobDef(name).label, g.name or ''), 'info')
        if source ~= 0 then Core.Notify(source, LP(source, 'jobs.set', jobDef(name).label, g.name or ''), 'success') end
        Core.Log('jobs', ('set %d -> %s[%d]'):format(target, name, grade), nil, nil)
    end
end, false)

AddEventHandler('playerDropped', function() Duty[source] = nil end)

-- ══════════════════════════════════════════════════════════════════
--  Admin-tunable settings (v-core module registry)
-- ══════════════════════════════════════════════════════════════════
-- Declared to v-core, which stores the values and serves them to the admin panel.
-- Applied back onto Config so the existing code paths see an operator's change without
-- a restart. See INTEGRATION.md.
local function declareSettings()
    Core.RegisterModule('v-jobs', {
        label = 'Jobs & salaries', category = 'civic',
        settings = {

            { key = 'payInterval', label = 'Pay every (minutes)', type = 'number', default = Config.PayInterval, min = 1, max = 240, step = 1 },
            { key = 'payAccount',  label = 'Paid into',          type = 'select', default = Config.PayAccount, options = { 'bank', 'cash' } },
            { key = 'salaryMult',  label = 'Salary multiplier',  type = 'number', default = 1.0, min = 0, max = 10 },
        },
    })
end

local function S(key, fallback) return Core.GetSetting('v-jobs', key, fallback) end

local function applySettings()

    Config.PayInterval = S('payInterval', Config.PayInterval)
    Config.PayAccount  = S('payAccount', Config.PayAccount)
    Config.SalaryMult  = S('salaryMult', 1.0)
end

AddEventHandler('v-core:server:settingChanged', function(mod)
    if mod == 'v-jobs' then applySettings() end
end)

CreateThread(function()
    Wait(2600)          -- let v-core's registry come up first
    declareSettings()
    applySettings()
end)
