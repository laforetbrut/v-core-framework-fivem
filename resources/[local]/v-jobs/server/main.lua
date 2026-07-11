-- v-jobs | server
-- Owns jobs/grades/duty/salaries and the exports other modules use to gate access.
local Core = exports['v-core']:GetCore()

local Duty = {}   -- [src] = bool (on/off duty; defaults on when holding a paid job)

local function jobDef(name) return Config.Jobs[name] end
local function gradeDef(name, grade)
    local j = Config.Jobs[name]
    return j and j.grades and j.grades[grade or 0] or nil
end

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
    return true
end)

exports('IsOnDuty', function(src) return isOnDuty(src) end)
exports('SetDuty',  function(src, on) Duty[src] = on and true or false end)

-- Label helpers for UIs.
exports('GetJobLabel', function(name) local j = jobDef(name); return j and j.label or name end)
exports('GetGradeLabel', function(name, grade) local g = gradeDef(name, grade); return g and g.name or '' end)

-- ── Salary loop ────────────────────────────────────────────────
CreateThread(function()
    local interval = (Config.PayInterval or 10) * 60000
    while true do
        Wait(interval)
        local account = Config.PayAccount or 'bank'
        for _, sid in ipairs(GetPlayers()) do
            local src = tonumber(sid)
            local p = src and Core.GetPlayer(src)
            if p and p.job and isOnDuty(src) then
                local g = gradeDef(p.job.name, p.job.grade)
                if g and (g.salary or 0) > 0 then
                    p.AddMoney(account, g.salary, 'salary')
                    Core.Notify(src, LP(src, 'jobs.paid', g.salary), 'success')
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
        local g = gradeDef(name, grade) or {}
        Core.Notify(target, LP(target, 'jobs.set', jobDef(name).label, g.name or ''), 'info')
        if source ~= 0 then Core.Notify(source, LP(source, 'jobs.set', jobDef(name).label, g.name or ''), 'success') end
        Core.Log('jobs', ('set %d -> %s[%d]'):format(target, name, grade), nil, nil)
    end
end, false)

AddEventHandler('playerDropped', function() Duty[source] = nil end)
