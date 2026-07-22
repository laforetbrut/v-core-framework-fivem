-- v-factions | server
-- One engine for legal factions (PD, EMS, mechanics) and illegal ones (gangs, mafias).
-- They differ by which table their definition lives in — `jobs` or `gangs` — and by
-- nothing else, which is what stops v-police and v-gangs from each growing their own copy
-- of membership and treasury code.
--
-- Everything that MUTATES takes the acting source and re-derives that player's rank
-- server-side. A boss menu that trusts the client is a money printer.

local Core

local function num(v, d) return tonumber(v) or d or 0 end
local function clean(s, n) return tostring(s or ''):sub(1, n or 50) end

local function kindOf(kind)
    kind = tostring(kind or 'job')
    return (kind == 'gang') and 'gang' or 'job'
end

local function tableFor(kind) return kindOf(kind) == 'gang' and 'gangs' or 'jobs' end
local function colFor(kind)
    if kindOf(kind) == 'gang' then return 'gang', 'gang_grade' end
    return 'job', 'job_grade'
end

-- ── Settings ──────────────────────────────────────────────────
V.Module({
    label = 'Factions', category = 'people',
    settings = {
        { key = 'treasury',        label = 'Faction treasuries enabled', type = 'bool',   default = Config.Treasury.enabled },
        { key = 'maxWithdraw',     label = 'Max withdrawal per action ($, 0 = unlimited)', type = 'number', default = Config.Treasury.maxWithdraw, min = 0, max = 100000000, step = 1000 },
        { key = 'allowNegative',   label = 'Allow a treasury to go negative', type = 'bool', default = Config.Treasury.allowNegative },
        { key = 'historyLimit',    label = 'Transactions shown',      type = 'number', default = Config.Treasury.historyLimit, min = 5, max = 500, step = 5 },
        { key = 'salaryFromTreasury', label = 'Pay salaries from the treasury', type = 'bool', default = Config.SalaryFromTreasury,
          hint = 'When on, an empty treasury means nobody gets paid.' },
        { key = 'bossFallback',    label = 'Highest grade counts as boss', type = 'bool', default = Config.BossFallbackHighestGrade },
        { key = 'startBalance',    label = 'Balance a new treasury opens with ($)', type = 'number', default = Config.Treasury.startBalance, min = 0, max = 100000000, step = 1000 },
        { key = 'logHires',        label = 'Log hires, fires and rank changes', type = 'bool', default = true },
    },
})

-- Consumers ask for the capability, not the resource: a server that replaces this
-- module keeps every consumer working.
V.Provide('factions')


-- ── Definitions ───────────────────────────────────────────────
-- Read straight from the same rows the admin panel already edits, so there is no second
-- copy of an organisation to drift out of sync.
local function decodeGrades(raw)
    if type(raw) == 'table' then return raw end
    local ok, parsed = pcall(json.decode, raw or '[]')
    return (ok and type(parsed) == 'table') and parsed or {}
end

local function getDef(name, kind)
    name = clean(name)
    if name == '' then return nil end
    local row = MySQL.single.await(
        ('SELECT name, label, type, grades FROM `%s` WHERE name = ?'):format(tableFor(kind)), { name })
    if not row then return nil end
    row.grades = decodeGrades(row.grades)
    row.kind = kindOf(kind)
    return row
end

local function gradeList(def)
    -- The seed writes grades as a map keyed by grade number; the admin panel writes an
    -- array. Accept both rather than making one of them wrong.
    local out = {}
    for k, g in pairs(def.grades or {}) do
        if type(g) == 'table' then
            out[#out + 1] = {
                grade  = math.floor(num(g.grade, tonumber(k) or 0)),
                name   = g.name or ('Grade ' .. tostring(k)),
                salary = math.floor(num(g.salary)),
                isboss = g.isboss == true or g.isboss == 1,
            }
        end
    end
    table.sort(out, function(a, b) return a.grade < b.grade end)
    return out
end

local function isBossGrade(def, grade)
    local list = gradeList(def)
    if #list == 0 then return false end
    grade = math.floor(num(grade))

    local anyFlagged = false
    for _, g in ipairs(list) do
        if g.isboss then
            anyFlagged = true
            if g.grade == grade then return true end
        end
    end
    -- An explicit flag anywhere means the data has an opinion: respect it exactly.
    if anyFlagged then return false end
    if not V.SettingBool('bossFallback', Config.BossFallbackHighestGrade) then return false end
    return grade >= list[#list].grade
end

-- ── Treasury ──────────────────────────────────────────────────
local function ensureAccount(name, kind)
    local k = kindOf(kind)
    local bal = MySQL.scalar.await(
        'SELECT balance FROM faction_accounts WHERE faction = ? AND kind = ?', { name, k })
    if bal == nil then
        bal = math.max(0, math.floor(num(V.Setting('startBalance', Config.Treasury.startBalance))))
        MySQL.insert.await('INSERT IGNORE INTO faction_accounts (faction, kind, balance) VALUES (?,?,?)',
            { name, k, bal })
    end
    return math.floor(num(bal))
end

local function record(name, kind, amount, balance, reason, byCid)
    MySQL.insert.await([[INSERT INTO faction_transactions
        (faction, kind, amount, balance, reason, by_cid) VALUES (?,?,?,?,?,?)]],
        { name, kindOf(kind), math.floor(amount), math.floor(balance), clean(reason, 60), byCid })
end

--- Move money in or out. `amount` is signed: negative withdraws. Returns the new balance,
--- or nil plus a reason — never a silent failure, because the caller is usually a UI that
--- has to tell somebody why.
local function move(name, kind, amount, reason, byCid)
    if not V.SettingBool('treasury', Config.Treasury.enabled) then return nil, 'disabled' end
    name = clean(name)
    local def = getDef(name, kind)
    if not def then return nil, 'faction' end

    amount = math.floor(num(amount))
    if amount == 0 then return nil, 'amount' end

    local maxW = math.floor(num(V.Setting('maxWithdraw', Config.Treasury.maxWithdraw)))
    if amount < 0 and maxW > 0 and -amount > maxW then return nil, 'limit' end

    local bal = ensureAccount(name, kind)
    local after = bal + amount
    if after < 0 and not V.SettingBool('allowNegative', Config.Treasury.allowNegative) then
        return nil, 'funds'
    end

    MySQL.update.await('UPDATE faction_accounts SET balance = ? WHERE faction = ? AND kind = ?',
        { after, name, kindOf(kind) })
    record(name, kind, amount, after, reason, byCid)
    TriggerEvent('v-factions:server:treasuryChanged', name, kindOf(kind), after, amount)
    return after
end

-- ── Membership ────────────────────────────────────────────────
local function members(name, kind)
    local col, gcol = colFor(kind)
    local rows = MySQL.query.await(
        ('SELECT citizenid, firstname, lastname, `%s` AS grade FROM characters WHERE `%s` = ? ORDER BY `%s` DESC, lastname')
            :format(gcol, col, gcol), { clean(name) }) or {}

    local def = getDef(name, kind)
    local labels = {}
    if def then for _, g in ipairs(gradeList(def)) do labels[g.grade] = g.name end end

    for _, r in ipairs(rows) do
        r.grade = math.floor(num(r.grade))
        r.gradeLabel = labels[r.grade] or tostring(r.grade)
        r.isboss = def and isBossGrade(def, r.grade) or false
        local p = Core.GetPlayerByCitizenId(r.citizenid)
        r.online = p and true or false
        r.source = p and p.source or nil
    end
    return rows
end

--- The rank of the acting player inside this faction, or nil if they are not in it.
local function myGrade(src, name, kind)
    local p = Core.GetPlayer(src)
    if not p then return nil end
    local slot = (kindOf(kind) == 'gang') and p.gang or p.job
    -- `player.job` is a TABLE, never a string: comparing it to one matches nothing and
    -- reads as "this feature is disabled for everyone".
    if type(slot) ~= 'table' or slot.name ~= clean(name) then return nil end
    return math.floor(num(slot.grade))
end

local function isBoss(src, name, kind)
    local grade = myGrade(src, name, kind)
    if grade == nil then return false end
    local def = getDef(name, kind)
    return def and isBossGrade(def, grade) or false
end

--- Write a membership change to the DB and, if the target is online, to the live player.
local function applyMembership(cid, name, kind, grade)
    local col, gcol = colFor(kind)
    MySQL.update.await(('UPDATE characters SET `%s` = ?, `%s` = ? WHERE citizenid = ?')
        :format(col, gcol), { clean(name), math.floor(num(grade)), cid })

    local p = Core.GetPlayerByCitizenId(cid)
    if p then
        if kindOf(kind) == 'gang' then p.SetGang(clean(name), math.floor(num(grade)))
        else p.SetJob(clean(name), math.floor(num(grade))) end
    end
    return true
end

--- Every membership change goes through here so the rank check and the audit entry can
--- never be forgotten by a caller.
local function changeMembership(bySrc, cid, name, kind, grade, action)
    cid = clean(cid, 32)
    if cid == '' then return false, 'target' end
    local def = getDef(name, kind)
    if not def then return false, 'faction' end

    -- bySrc == nil means the server itself (admin panel, a script). A player caller must
    -- be a boss of THIS faction — not an admin, a boss: the two are different powers.
    if bySrc and not isBoss(bySrc, name, kind) then return false, 'rank' end

    grade = math.floor(num(grade))
    local valid, top = false, 0
    for _, g in ipairs(gradeList(def)) do
        if g.grade == grade then valid = true end
        if g.grade > top then top = g.grade end
    end
    if action ~= 'fire' and not valid then return false, 'grade' end

    -- A boss cannot promote anyone above themselves, which is how a faction gets taken
    -- over from the inside.
    if bySrc and action ~= 'fire' then
        local mine = myGrade(bySrc, name, kind) or 0
        if grade > mine then return false, 'rank' end
    end

    local byCid
    if bySrc then
        local bp = Core.GetPlayer(bySrc)
        byCid = bp and bp.citizenid or nil
    end

    if action == 'fire' then
        local defaultName = (kindOf(kind) == 'gang') and 'none' or 'unemployed'
        applyMembership(cid, defaultName, kind, 0)
    else
        applyMembership(cid, name, kind, grade)
    end

    if V.SettingBool('logHires', true) then
        Core.Log('factions', ('%s: %s %s (%s grade %d)'):format(
            name, action, cid, kindOf(kind), grade), nil, byCid)
    end
    TriggerEvent('v-factions:server:membershipChanged', name, kindOf(kind), cid, action, grade)
    return true
end

-- ── Exports ───────────────────────────────────────────────────
exports('Get',        function(name, kind) return getDef(name, kind) end)
exports('GetGrades',  function(name, kind)
    local def = getDef(name, kind); return def and gradeList(def) or {}
end)
exports('GetMembers', function(name, kind) return members(name, kind) end)
exports('IsBoss',     function(src, name, kind) return isBoss(src, name, kind) end)
exports('GetGrade',   function(src, name, kind) return myGrade(src, name, kind) end)

exports('Hire',     function(bySrc, cid, name, kind, grade)
    return changeMembership(bySrc, cid, name, kind, grade or 0, 'hire')
end)
exports('Fire',     function(bySrc, cid, name, kind)
    return changeMembership(bySrc, cid, name, kind, 0, 'fire')
end)
exports('SetGrade', function(bySrc, cid, name, kind, grade)
    return changeMembership(bySrc, cid, name, kind, grade, 'grade')
end)

exports('GetBalance', function(name, kind) return ensureAccount(clean(name), kind) end)
exports('Deposit',    function(name, kind, amount, reason, byCid)
    return move(name, kind, math.abs(math.floor(num(amount))), reason or 'deposit', byCid)
end)
exports('Withdraw',   function(name, kind, amount, reason, byCid)
    return move(name, kind, -math.abs(math.floor(num(amount))), reason or 'withdraw', byCid)
end)
exports('GetTransactions', function(name, kind, limit)
    limit = math.min(500, math.max(1, math.floor(num(limit, V.Setting('historyLimit', Config.Treasury.historyLimit)))))
    return MySQL.query.await(
        'SELECT amount, balance, reason, by_cid, at FROM faction_transactions ' ..
        'WHERE faction = ? AND kind = ? ORDER BY id DESC LIMIT ' .. limit,
        { clean(name), kindOf(kind) }) or {}
end)

--- Salary source for v-jobs. Returns true when the money came out of the treasury, false
--- when the treasury could not cover it, and nil when this faction is not on treasury pay
--- at all — three distinct answers, because the caller has to treat them differently.
exports('TrySalary', function(name, kind, amount, cid)
    if not V.SettingBool('salaryFromTreasury', Config.SalaryFromTreasury) then return nil end
    if not V.SettingBool('treasury', Config.Treasury.enabled) then return nil end
    amount = math.floor(num(amount))
    if amount <= 0 then return nil end
    local ok = move(name, kind, -amount, 'salary', cid)
    return ok ~= nil
end)

exports('ListFactions', function(kind)
    local rows = MySQL.query.await(
        ('SELECT name, label, type FROM `%s` ORDER BY label'):format(tableFor(kind))) or {}
    for _, r in ipairs(rows) do
        r.kind = kindOf(kind)
        r.balance = ensureAccount(r.name, kind)
    end
    return rows
end)

-- ── Boot ──────────────────────────────────────────────────────
CreateThread(function()
    while GetResourceState('oxmysql') ~= 'started' do Wait(100) end

    MySQL.query.await([[CREATE TABLE IF NOT EXISTS `faction_accounts` (
        `faction` VARCHAR(50) NOT NULL,
        `kind` VARCHAR(8) NOT NULL DEFAULT 'job',        -- job | gang
        `balance` BIGINT NOT NULL DEFAULT 0,
        `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        PRIMARY KEY (`faction`, `kind`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])

    -- The audit trail is the point of a treasury: a balance nobody can explain is
    -- indistinguishable from a duplication bug.
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS `faction_transactions` (
        `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
        `faction` VARCHAR(50) NOT NULL,
        `kind` VARCHAR(8) NOT NULL DEFAULT 'job',
        `amount` BIGINT NOT NULL,
        `balance` BIGINT NOT NULL,
        `reason` VARCHAR(60) NOT NULL DEFAULT '',
        `by_cid` VARCHAR(32) DEFAULT NULL,
        `at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (`id`), KEY `fac_idx` (`faction`, `kind`, `id`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
end)

V.Ready(function(core)
    Core = core
end)
