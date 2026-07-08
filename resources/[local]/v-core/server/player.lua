-- v-core | player model
-- In-memory player object. Database persistence (oxmysql) plugs in here later.
VCore = VCore or {}

--- Build a fresh player object for a connected source.
--- @param source number
--- @return table player
function VCore.CreatePlayer(source)
    local self = {
        source  = source,
        name    = GetPlayerName(source) or 'Unknown',
        license = VCore.GetLicense(source),
        money   = {
            cash = Config.StartingMoney.cash,
            bank = Config.StartingMoney.bank,
        },
    }

    --- Add money to an account. Returns the new balance, or nil on invalid input.
    function self.AddMoney(account, amount)
        if not self.money[account] or amount <= 0 then return nil end
        self.money[account] = self.money[account] + amount
        return self.money[account]
    end

    --- Remove money if the account can cover it. Returns true on success.
    function self.RemoveMoney(account, amount)
        if not self.money[account] or amount <= 0 then return false end
        if self.money[account] < amount then return false end
        self.money[account] = self.money[account] - amount
        return true
    end

    return self
end
