
-- Consumers ask for the capability, not the resource: a server that replaces this
-- module keeps every consumer working.
V.Provide('banking')
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
    local maxW = math.floor(tonumber(Core.GetSetting('v-banking', 'maxWithdraw', Config.MaxWithdraw)) or 0)
    if maxW > 0 and amount > maxW then resolve({ error = 'maxwithdraw', limit = maxW }) return end
    if not p.RemoveMoney('bank', amount, 'bank-withdraw') then resolve({ error = 'funds' }) return end
    p.AddMoney('cash', amount, 'bank-withdraw')
    V.Use('v-3dsound').PlayFor(src, 'money')
    recordTx(p.citizenid, 'withdraw', amount, p.money.bank, nil)
    Core.Log('bank', ('%s withdraw %d'):format(p.citizenid, amount), nil, p.citizenid)
    resolve(state(p))
end)

-- ══════════════════════════════════════════════════════════════
-- The card
-- ══════════════════════════════════════════════════════════════
-- Minted once per character and kept in their metadata. It exists for the same reason a
-- phone number does: a citizen id is a database key, and asking players to trade one so
-- they can be paid is asking them to hand over an internal identifier.
--
-- Four groups of four, Fleeca's own prefix. Retried on collision -- two characters made
-- in the same second would otherwise share an account number, which is the one mistake
-- a bank cannot make.
local function mintCard()
    local out = { '4' .. tostring(math.random(100, 999)) }
    for _ = 1, 3 do out[#out + 1] = string.format('%04d', math.random(0, 9999)) end
    return table.concat(out, ' ')
end

--- Read only. A character has a card because they ordered one, not because they once
--- opened their wallet.
local function cardOf(player)
    if not player then return nil end
    local m = player.GetMetadata('bankcard')
    return (type(m) == 'string' and m ~= '') and m or nil
end

--- Mint one, retried on collision. Two characters made in the same second would otherwise
--- share an account number, which is the one mistake a bank cannot make.
local function issueCard(player)
    for _ = 1, 40 do
        local n = mintCard()
        local taken = MySQL.scalar.await(
            "SELECT 1 FROM characters WHERE JSON_EXTRACT(metadata, '$.bankcard') = ? LIMIT 1", { n })
        if not taken then
            player.SetMetadata('bankcard', n)
            return n
        end
    end
    return nil
end

--- The citizen id behind a card number, or nil. Used to let a transfer address a card.
local function cidOfCard(card)
    return MySQL.scalar.await(
        "SELECT citizenid FROM characters WHERE JSON_EXTRACT(metadata, '$.bankcard') = ? LIMIT 1",
        { card })
end

exports('GetCard', function(src) return cardOf(Core.GetPlayer(src)) end)
exports('FindByCard', function(card) return cidOfCard(tostring(card or '')) end)

Core.RegisterCallback('v-banking:card', function(source, resolve)
    local p = Core.GetPlayer(source)
    if not p then resolve(false) return end
    resolve({
        ok = true,
        card = cardOf(p),                       -- nil until one has been ordered
        fee = math.floor(tonumber(Core.GetSetting('v-banking', 'cardFee', Config.CardFee)) or 0),
        holder = ((p.firstname or '') .. ' ' .. (p.lastname or '')):upper(),
        bank = p.money.bank,
    })
end)

--- Order a card. Charged, logged, and refused if it would leave the account short --
--- a bank that issues a card it could not charge for has given one away.
Core.RegisterCallback('v-banking:requestCard', function(source, resolve)
    local p = Core.GetPlayer(source)
    if not p then resolve(false) return end
    if cardOf(p) then resolve({ error = 'hascard' }) return end

    local fee = math.floor(tonumber(Core.GetSetting('v-banking', 'cardFee', Config.CardFee)) or 0)
    if fee > 0 and not p.RemoveMoney('bank', fee, 'bank-card') then
        resolve({ error = 'funds' }) return
    end

    local card = issueCard(p)
    if not card then
        -- Could not mint: give the money back rather than charging for nothing.
        if fee > 0 then p.AddMoney('bank', fee, 'bank-card-refund') end
        resolve({ error = 'x' }) return
    end

    if fee > 0 then recordTx(p.citizenid, 'fee', fee, p.money.bank, 'card') end
    Core.Log('bank', ('%s ordered a card for %d'):format(p.citizenid, fee), nil, p.citizenid)
    resolve({ ok = true, card = card, bank = p.money.bank })
end)


Core.RegisterCallback('v-banking:transfer', function(source, resolve, data)
    local p = Core.GetPlayer(source)
    local amount = math.floor(tonumber(data and data.amount) or 0)
    local targetCid = tostring((data and data.target) or ''):upper()
    -- A card number is what one player actually gives another, so accept it here rather
    -- than making the phone translate it: the translation belongs next to the mint.
    if targetCid:find('%d%d%d%d') and targetCid:find(' ') then
        targetCid = tostring(cidOfCard(targetCid) or ''):upper()
    end
    if not p or amount <= 0 or targetCid == '' or targetCid == p.citizenid then resolve(false) return end

    local minT = math.floor(tonumber(Core.GetSetting('v-banking', 'minTransfer', Config.MinTransfer)) or 1)
    local maxT = math.floor(tonumber(Core.GetSetting('v-banking', 'maxTransfer', Config.MaxTransfer)) or 0)
    if amount < minT then resolve({ error = 'mintransfer', limit = minT }) return end
    if maxT > 0 and amount > maxT then resolve({ error = 'maxtransfer', limit = maxT }) return end

    -- The fee is charged ON TOP, so the recipient always receives exactly `amount` —
    -- a transfer that silently arrives short is the kind of thing players report as theft.
    local rate = tonumber(Core.GetSetting('v-banking', 'transferFee', Config.TransferFee)) or 0.0
    local fee = math.floor(amount * math.max(0.0, math.min(1.0, rate)))

    -- Validate recipient exists before touching money.
    local exists = MySQL.scalar.await('SELECT 1 FROM characters WHERE citizenid = ?', { targetCid })
    if not exists then resolve({ error = 'target' }) return end

    if not p.RemoveMoney('bank', amount + fee, 'bank-transfer') then resolve({ error = 'funds' }) return end
    if fee > 0 then recordTx(p.citizenid, 'fee', fee, p.money.bank, nil) end

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
            { 'UPDATE characters SET bank = bank - ? WHERE citizenid = ?', { amount + fee, p.citizenid } },
            { 'UPDATE characters SET bank = bank + ? WHERE citizenid = ?', { amount, targetCid } },
        })
        local newBal = MySQL.scalar.await('SELECT bank FROM characters WHERE citizenid = ?', { targetCid }) or 0
        recordTx(targetCid, 'transfer_in', amount, newBal, p.citizenid)
    end

    recordTx(p.citizenid, 'transfer_out', amount, p.money.bank, targetCid)
    Core.Log('bank', ('%s transfer %d -> %s'):format(p.citizenid, amount, targetCid), nil, p.citizenid)
    resolve(state(p))
end)

-- ══════════════════════════════════════════════════════════════════
--  Admin-tunable settings (v-core module registry)
-- ══════════════════════════════════════════════════════════════════
-- Declared to v-core, which stores the values and serves them to the admin panel.
-- Applied back onto Config so the existing code paths see an operator's change without
-- a restart. See DEVELOPERS.md.
local function declareSettings()
    Core.RegisterModule('v-banking', {
        label = 'Banking', category = 'economy',
        settings = {

            { key = 'distance',     label = 'ATM range (m)',        type = 'number', default = Config.Distance, min = 0.5, max = 10 },
            { key = 'historyLimit', label = 'Transactions shown',   type = 'number', default = Config.HistoryLimit, min = 5, max = 200, step = 1 },
            { key = 'cardFee', label = 'Cost of a bank card ($)', type = 'number',
              default = Config.CardFee, min = 0, max = 100000, step = 10,
              hint = 'Charged when a character orders their card. 0 makes them free, but still ordered rather than issued automatically.' },
            { key = 'transferFee',  label = 'Transfer fee (0.02 = 2%)', type = 'number', default = Config.TransferFee, min = 0, max = 1, step = 0.005 },
            { key = 'minTransfer',  label = 'Minimum transfer ($)',  type = 'number', default = Config.MinTransfer, min = 1, max = 100000, step = 1 },
            { key = 'maxTransfer',  label = 'Maximum transfer ($, 0 = unlimited)', type = 'number', default = Config.MaxTransfer, min = 0, max = 100000000, step = 100 },
            { key = 'maxWithdraw',  label = 'Max ATM withdrawal ($, 0 = unlimited)', type = 'number', default = Config.MaxWithdraw, min = 0, max = 100000000, step = 100 },
        },
    })
end

local function S(key, fallback) return Core.GetSetting('v-banking', key, fallback) end

local function applySettings()

    Config.Distance     = S('distance', Config.Distance)
    Config.HistoryLimit = S('historyLimit', Config.HistoryLimit)
end

AddEventHandler('v-core:server:settingChanged', function(mod)
    if mod == 'v-banking' then applySettings() end
end)

V.Ready(function()
    declareSettings()
    applySettings()
end)
