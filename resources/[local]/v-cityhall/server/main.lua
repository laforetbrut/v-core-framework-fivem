-- v-cityhall | server
-- Hands out the jobs an admin has left open. Server-authoritative: the player must be
-- physically at a city hall, the job must exist, must not be whitelisted and must not be
-- in Config.NeverPublic. Grade is always 0 — the city hall hires at entry level only.
local Core = exports['v-core']:GetCore()

local never = {}
for _, n in ipairs(Config.NeverPublic or {}) do never[n] = true end

-- Is `src` standing at a city hall? Coordinates are re-read from the server-owned ped.
local function atCityHall(src)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return false end
    local c = GetEntityCoords(ped)
    for _, l in ipairs(Config.Locations) do
        if #(c - vector3(l.x, l.y, l.z)) <= (Config.Distance + 2.0) then return true end
    end
    return false
end

-- The open jobs, newest definition first. Falls back to v-jobs' own defs while v-world
-- is still booting so the desk is never empty.
local function openJobs()
    local out = {}
    local rows = exports['v-world']:IsReady() and exports['v-world']:GetJobs() or nil
    if rows then
        for _, j in ipairs(rows) do
            if j.whitelisted ~= 1 and not never[j.name] then
                local base = j.grades and j.grades[1] or nil
                out[#out + 1] = {
                    name   = j.name,
                    label  = j.label or j.name,
                    type   = j.type or 'civ',
                    grade  = base and base.name or '',
                    salary = base and base.salary or 0,
                    ranks  = #(j.grades or {}),
                }
            end
        end
    end
    table.sort(out, function(a, b) return a.label < b.label end)
    return out
end

Core.RegisterCallback('v-cityhall:getJobs', function(source, resolve)
    if not atCityHall(source) then resolve(false); return end
    local p = Core.GetPlayer(source)
    if not p then resolve(false); return end
    -- player.job is a table { name, grade }
    local cur   = (p.job and p.job.name) or 'unemployed'
    local grade = (p.job and p.job.grade) or 0
    resolve({
        jobs    = openJobs(),
        current = cur,
        label   = exports['v-jobs']:GetJobLabel(cur),
        grade   = exports['v-jobs']:GetGradeLabel(cur, grade),
        fee     = Config.HireFee or 0,
        cash    = p.money and p.money.cash or 0,
    })
end)

Core.RegisterCallback('v-cityhall:take', function(source, resolve, data)
    if not atCityHall(source) then resolve({ error = 'far' }); return end
    local p = Core.GetPlayer(source)
    if not p then resolve(false); return end

    local want = type(data) == 'table' and tostring(data.job or '') or ''
    if want == '' or never[want] then resolve({ error = 'invalid' }); return end
    if p.job and p.job.name == want then resolve({ error = 'already' }); return end

    -- Re-derive the allowed set server-side: never trust the list the NUI was shown.
    local ok = false
    for _, j in ipairs(openJobs()) do
        if j.name == want then ok = true; break end
    end
    if not ok then resolve({ error = 'whitelisted' }); return end

    local fee = Config.HireFee or 0
    if fee > 0 and not p.RemoveMoney('cash', fee, 'cityhall-fee') then
        resolve({ error = 'funds' }); return
    end

    if not exports['v-jobs']:SetJob(source, want, 0) then
        if fee > 0 then p.AddMoney('cash', fee, 'cityhall-refund') end   -- charge must not strand the player
        resolve({ error = 'invalid' }); return
    end

    Core.Log('jobs', ('took the job %s at the city hall'):format(want), { fee = fee }, p.citizenid)
    Core.Notify(source, LP(source, 'cityhall.hired', exports['v-jobs']:GetJobLabel(want)), 'success')
    resolve({ ok = true })
end)

Core.RegisterCallback('v-cityhall:resign', function(source, resolve)
    if not atCityHall(source) then resolve({ error = 'far' }); return end
    local p = Core.GetPlayer(source)
    if not p then resolve(false); return end
    local was = (p.job and p.job.name) or 'unemployed'
    if was == 'unemployed' then resolve({ error = 'already' }); return end
    if not exports['v-jobs']:SetJob(source, 'unemployed', 0) then resolve(false); return end
    Core.Log('jobs', ('resigned from %s at the city hall'):format(was), nil, p.citizenid)
    Core.Notify(source, LP(source, 'cityhall.resigned'), 'info')
    resolve({ ok = true })
end)

-- ── Admin-tunable settings ─────────────────────────────────────
local function declareSettings()
    Core.RegisterModule('v-cityhall', {
        label = 'City hall', category = 'civic',
        settings = {
            { key = 'blips',     label = 'Show city hall blips', type = 'bool', default = true },
            { key = 'fee',       label = 'Fee to change job ($)', type = 'number', default = 0, min = 0, max = 100000, step = 50 },
            { key = 'hireFee',  label = 'Hiring filing fee ($)', type = 'number', default = Config.HireFee, min = 0, max = 100000, step = 1 },
            { key = 'distance', label = 'Interaction range (m)', type = 'number', default = Config.Distance, min = 1, max = 15 },
        },
    })
end

local function applySettings()
    Config.HireFee  = Core.GetSetting('v-cityhall', 'hireFee', Config.HireFee)
    Config.Distance = Core.GetSetting('v-cityhall', 'distance', Config.Distance)
end

AddEventHandler('v-core:server:settingChanged', function(mod)
    if mod == 'v-cityhall' then applySettings() end
end)

CreateThread(function()
    Wait(2500)
    declareSettings()
    applySettings()
end)

-- The world content this module owns is seeded from config once, then read from the
-- database so an operator's edits in the admin panel survive a restart.
CreateThread(function()
    while GetResourceState('v-world') ~= 'started' do Wait(200) end
    local tries = 0
    while not exports['v-world']:IsReady() and tries < 150 do Wait(100); tries = tries + 1 end
    if not exports['v-world']:IsReady() then return end
    exports['v-world']:SeedCityHalls(Config.Locations or {})
end)

-- ── Open positions, for anyone who wants to show them elsewhere ──
-- The phone lists vacancies; **taking** a job still happens at a desk, because signing on
-- is the roleplay act and `v-cityhall:take` is gated on standing at one. Exporting the
-- list rather than letting a second module rebuild it keeps one definition of "open".
exports('OpenPositions', function() return openJobs() end)
