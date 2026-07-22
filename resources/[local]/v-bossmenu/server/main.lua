-- v-bossmenu | server
-- Every callback here re-derives the caller's rank through v-factions before doing
-- anything. A boss menu that trusts the client is a money printer, and the client is the
-- one place this framework never trusts.
--
-- The menu owns no data: membership and the treasury both live in v-factions. This file
-- is the rank gate plus the shape the NUI wants.

local Core
local function num(v, d) return tonumber(v) or d or 0 end
local function fac() return V.Use('v-factions') end

local function L(src, k)
    local p = Core and Core.GetPlayer(src)
    local lang = (p and p.lang) or 'fr'
    return (Locales[lang] or Locales.fr or {})[k] or k
end

-- ── Settings ──────────────────────────────────────────────────
V.Module({
    label = 'Boss menu', category = 'people',
    settings = {
        { key = 'allowHire',     label = 'Bosses can hire',            type = 'bool',   default = Config.Allow.hire },
        { key = 'allowFire',     label = 'Bosses can dismiss',         type = 'bool',   default = Config.Allow.fire },
        { key = 'allowPromote',  label = 'Bosses can change ranks',    type = 'bool',   default = Config.Allow.promote },
        { key = 'allowTreasury', label = 'Bosses can move treasury money', type = 'bool', default = Config.Allow.treasury },
        { key = 'allowSalaries', label = 'Bosses can pay salaries by hand', type = 'bool', default = Config.Allow.paySalaries },
        { key = 'hireRadius',    label = 'Hiring range (m)',           type = 'number', default = Config.HireRadius, min = 1, max = 30, step = 0.5 },
        { key = 'salaryMult',    label = 'Manual salary multiplier',   type = 'number', default = Config.SalaryMult, min = 0, max = 10, step = 0.05 },
        { key = 'gangs',         label = 'Gangs get a boss menu too',  type = 'bool',   default = true },
    },
})

-- ── Which faction is this player the boss of? ─────────────────
-- A character can hold a job and a gang at once, so both are checked. The job wins when
-- somebody is boss of both, and the client can ask for the other explicitly.
local function bossOf(src, want)
    local f = fac()
    local p = Core.GetPlayer(src)
    if not p then return nil end

    local order = { { 'job', p.job }, { 'gang', p.gang } }
    if want == 'gang' then order = { { 'gang', p.gang }, { 'job', p.job } } end

    for _, pair in ipairs(order) do
        local kind, slot = pair[1], pair[2]
        if kind ~= 'gang' or V.SettingBool('gangs', true) then
            -- `player.job` is a TABLE, never a string.
            if type(slot) == 'table' and slot.name and slot.name ~= ''
               and slot.name ~= 'unemployed' and slot.name ~= 'none' then
                if f.IsBoss(src, slot.name, kind) then return slot.name, kind end
            end
        end
    end
    return nil
end

-- ── Nearby, hireable players ──────────────────────────────────
-- Server-derived: the client sends nothing but "open the menu".
local function nearby(src, name, kind)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return {} end
    local origin = GetEntityCoords(ped)
    local radius = num(V.Setting('hireRadius', Config.HireRadius), Config.HireRadius)

    local out = {}
    for _, sid in ipairs(GetPlayers()) do
        local tid = tonumber(sid)
        if tid and tid ~= src then
            local tped = GetPlayerPed(tid)
            if tped and tped ~= 0 and #(GetEntityCoords(tped) - origin) <= radius then
                local tp = Core.GetPlayer(tid)
                if tp then
                    local slot = (kind == 'gang') and tp.gang or tp.job
                    local already = type(slot) == 'table' and slot.name == name
                    out[#out + 1] = {
                        citizenid = tp.citizenid,
                        name = ('%s %s'):format(tp.firstname or '', tp.lastname or ''),
                        already = already,
                    }
                end
            end
        end
    end
    return out
end

-- ── Open ──────────────────────────────────────────────────────
V.Callback('v-bossmenu:open', function(src, resolve, want)
    local f = fac()
    local name, kind = bossOf(src, want)
    if not name then resolve({ error = 'rank' }) return end

    local def = f.Get(name, kind)
    local members = f.GetMembers(name, kind) or {}

    -- Duty is v-jobs' business; asking it keeps one source of truth.
    local duty = V.Use('v-jobs')
    for _, m in ipairs(members) do
        m.duty = (m.online and m.source) and (duty.IsOnDuty(m.source) == true) or false
    end

    resolve({
        faction = { name = name, kind = kind, label = def and def.label or name },
        grades  = f.GetGrades(name, kind) or {},
        members = members,
        nearby  = nearby(src, name, kind),
        balance = f.GetBalance(name, kind) or 0,
        history = f.GetTransactions(name, kind) or {},
        can = {
            hire     = V.SettingBool('allowHire', Config.Allow.hire),
            fire     = V.SettingBool('allowFire', Config.Allow.fire),
            promote  = V.SettingBool('allowPromote', Config.Allow.promote),
            treasury = V.SettingBool('allowTreasury', Config.Allow.treasury),
            salaries = V.SettingBool('allowSalaries', Config.Allow.paySalaries),
        },
        myGrade = f.GetGrade(src, name, kind) or 0,
    })
end)

-- ── Membership ────────────────────────────────────────────────
-- One helper so the rank gate and the "is this action even enabled" check can never be
-- forgotten by one of the three callbacks below.
local function gated(src, settingKey, default, fn)
    local name, kind = bossOf(src)
    if not name then return { error = 'rank' } end
    if not V.SettingBool(settingKey, default) then return { error = 'off' } end
    return fn(name, kind)
end

V.Callback('v-bossmenu:hire', function(src, resolve, data)
    if type(data) ~= 'table' then resolve(false) return end
    resolve(gated(src, 'allowHire', Config.Allow.hire, function(name, kind)
        -- Only somebody actually standing here: re-derived, never taken from the payload.
        local cid = tostring(data.cid or '')
        local found = false
        for _, n in ipairs(nearby(src, name, kind)) do
            if n.citizenid == cid then found = true break end
        end
        if not found then return { error = 'far' } end

        local ok, why = fac().Hire(src, cid, name, kind, math.floor(num(data.grade)))
        if not ok then return { error = why or 'x' } end
        return { ok = true }
    end))
end)

V.Callback('v-bossmenu:fire', function(src, resolve, data)
    if type(data) ~= 'table' then resolve(false) return end
    resolve(gated(src, 'allowFire', Config.Allow.fire, function(name, kind)
        local cid = tostring(data.cid or '')
        local p = Core.GetPlayer(src)
        -- A boss firing themselves leaves an organisation with a treasury and nobody who
        -- can reach it.
        if p and p.citizenid == cid then return { error = 'self' } end
        local ok, why = fac().Fire(src, cid, name, kind)
        if not ok then return { error = why or 'x' } end
        return { ok = true }
    end))
end)

V.Callback('v-bossmenu:setGrade', function(src, resolve, data)
    if type(data) ~= 'table' then resolve(false) return end
    resolve(gated(src, 'allowPromote', Config.Allow.promote, function(name, kind)
        local ok, why = fac().SetGrade(src, tostring(data.cid or ''), name, kind, math.floor(num(data.grade)))
        if not ok then return { error = why or 'x' } end
        return { ok = true }
    end))
end)

-- ── Treasury ──────────────────────────────────────────────────
V.Callback('v-bossmenu:deposit', function(src, resolve, data)
    if type(data) ~= 'table' then resolve(false) return end
    resolve(gated(src, 'allowTreasury', Config.Allow.treasury, function(name, kind)
        local p = Core.GetPlayer(src)
        local amount = math.floor(num(data.amount))
        if not p or amount <= 0 then return { error = 'amount' } end

        -- Take the money FIRST, then credit the treasury: if the treasury write fails the
        -- player is refunded, whereas the other order would mint money on a failure.
        if not p.RemoveMoney('bank', amount, 'faction-deposit') then return { error = 'funds' } end
        local after = fac().Deposit(name, kind, amount, 'deposit', p.citizenid)
        if after == nil then
            p.AddMoney('bank', amount, 'faction-deposit-refund')
            return { error = 'disabled' }
        end
        return { ok = true, balance = after }
    end))
end)

V.Callback('v-bossmenu:withdraw', function(src, resolve, data)
    if type(data) ~= 'table' then resolve(false) return end
    resolve(gated(src, 'allowTreasury', Config.Allow.treasury, function(name, kind)
        local p = Core.GetPlayer(src)
        local amount = math.floor(num(data.amount))
        if not p or amount <= 0 then return { error = 'amount' } end

        -- v-factions owns the ceiling and the overdraft rule; asking it rather than
        -- re-implementing them here is what keeps the two from drifting apart.
        local after, why = fac().Withdraw(name, kind, amount, 'withdraw', p.citizenid)
        if after == nil then return { error = why or 'funds' } end
        p.AddMoney('bank', amount, 'faction-withdraw')
        return { ok = true, balance = after }
    end))
end)

V.Callback('v-bossmenu:paySalaries', function(src, resolve)
    resolve(gated(src, 'allowSalaries', Config.Allow.paySalaries, function(name, kind)
        local f = fac()
        local mult = num(V.Setting('salaryMult', Config.SalaryMult), Config.SalaryMult)
        local duty = V.Use('v-jobs')

        local salaries = {}
        for _, g in ipairs(f.GetGrades(name, kind) or {}) do salaries[g.grade] = g.salary end

        local paid, total, short = 0, 0, false
        for _, m in ipairs(f.GetMembers(name, kind) or {}) do
            local onDuty = m.online and m.source and duty.IsOnDuty(m.source) == true
            local pay = math.floor(num(salaries[m.grade]) * mult)
            if onDuty and pay > 0 then
                -- One withdrawal per member, so a treasury that runs dry pays the first
                -- few rather than failing the whole run and paying nobody.
                local after = f.Withdraw(name, kind, pay, 'salary', m.citizenid)
                if after == nil then short = true break end
                local tp = Core.GetPlayerByCitizenId(m.citizenid)
                if tp then
                    tp.AddMoney('bank', pay, 'salary')
                    Core.Notify(tp.source, L(tp.source, 'boss.got_paid'):format(pay), 'success')
                end
                paid, total = paid + 1, total + pay
            end
        end

        Core.Log('factions', ('%s paid %d salary/salaries totalling %d'):format(name, paid, total),
            nil, (Core.GetPlayer(src) or {}).citizenid)
        return { ok = true, paid = paid, total = total, short = short }
    end))
end)

V.Ready(function(core) Core = core end)
