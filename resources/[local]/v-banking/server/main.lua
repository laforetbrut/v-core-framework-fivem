-- v-banking | server
local Core = exports['v-core']:GetCore()

local function recordTx(citizenid, txtype, amount, balanceAfter, label)
    -- awaited: history() runs a SELECT immediately after, and a fire-and-forget insert
    -- can land on another pool connection AFTER it -> the fresh row would be missing
    -- from the "recent activity" list the player sees.
    MySQL.insert.await('INSERT INTO bank_transactions (citizenid, type, amount, balance_after, label) VALUES (?, ?, ?, ?, ?)',
        { citizenid, txtype, amount, balanceAfter, label })
end

local function history(citizenid)
    return MySQL.query.await(
        'SELECT type, amount, balance_after, label, created_at FROM bank_transactions WHERE citizenid = ? ORDER BY id DESC LIMIT ?',
        { citizenid, Config.HistoryLimit }) or {}
end

local function state(player)
    return { cash = player.money.cash, bank = player.money.bank, transactions = history(player.citizenid) }
end

Core.RegisterCallback('v-banking:getData', function(source, resolve)
    local p = Core.GetPlayer(source)
    if not p then resolve(false) return end
    resolve(state(p))
end)

Core.RegisterCallback('v-banking:deposit', function(source, resolve, amount)
    local p = Core.GetPlayer(source)
    amount = math.floor(tonumber(amount) or 0)
    if not p or amount <= 0 then resolve(false) return end
    if not p.RemoveMoney('cash', amount, 'bank-deposit') then resolve({ error = 'funds' }) return end
    p.AddMoney('bank', amount, 'bank-deposit')
    recordTx(p.citizenid, 'deposit', amount, p.money.bank, nil)
    Core.Log('bank', ('%s deposit %d'):format(p.citizenid, amount), nil, p.citizenid)
    resolve(state(p))
end)

Core.RegisterCallback('v-banking:withdraw', function(source, resolve, amount)
    local p = Core.GetPlayer(source)
    amount = math.floor(tonumber(amount) or 0)
    if not p or amount <= 0 then resolve(false) return end
    if not p.RemoveMoney('bank', amount, 'bank-withdraw') then resolve({ error = 'funds' }) return end
    p.AddMoney('cash', amount, 'bank-withdraw')
    recordTx(p.citizenid, 'withdraw', amount, p.money.bank, nil)
    Core.Log('bank', ('%s withdraw %d'):format(p.citizenid, amount), nil, p.citizenid)
    resolve(state(p))
end)

Core.RegisterCallback('v-banking:transfer', function(source, resolve, data)
    local p = Core.GetPlayer(source)
    local amount = math.floor(tonumber(data and data.amount) or 0)
    local targetCid = tostring((data and data.target) or ''):upper()
    if not p or amount <= 0 or targetCid == '' or targetCid == p.citizenid then resolve(false) return end

    -- Validate recipient exists before touching money.
    local exists = MySQL.scalar.await('SELECT 1 FROM characters WHERE citizenid = ?', { targetCid })
    if not exists then resolve({ error = 'target' }) return end

    if not p.RemoveMoney('bank', amount, 'bank-transfer') then resolve({ error = 'funds' }) return end

    local target = Core.GetPlayerByCitizenId(targetCid)
    if target then
        target.AddMoney('bank', amount, 'bank-transfer')
        recordTx(target.citizenid, 'transfer_in', amount, target.money.bank, p.citizenid)
        Core.Notify(target.source, ('Virement reçu: $%d'):format(amount), 'success')
    else
        -- Offline recipient: debit the (online) sender AND credit the recipient in ONE
        -- atomic DB write, so a crash before the sender's next autosave can't duplicate
        -- the money. The sender's in-memory RemoveMoney above already keeps the live
        -- session correct; this just flushes that deduction durably now.
        MySQL.transaction.await({
            { 'UPDATE characters SET bank = bank - ? WHERE citizenid = ?', { amount, p.citizenid } },
            { 'UPDATE characters SET bank = bank + ? WHERE citizenid = ?', { amount, targetCid } },
        })
        local newBal = MySQL.scalar.await('SELECT bank FROM characters WHERE citizenid = ?', { targetCid }) or 0
        recordTx(targetCid, 'transfer_in', amount, newBal, p.citizenid)
    end

    recordTx(p.citizenid, 'transfer_out', amount, p.money.bank, targetCid)
    Core.Log('bank', ('%s transfer %d -> %s'):format(p.citizenid, amount, targetCid), nil, p.citizenid)
    resolve(state(p))
end)
