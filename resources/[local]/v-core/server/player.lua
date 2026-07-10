-- v-core | player object
-- Rich, self-persisting player model built from a database row.
VCore = VCore or {}

--- Build the in-memory player object from a `characters` row.
--- @param source number
--- @param row table  a row from the characters table
--- @return table player
function VCore.NewPlayer(source, row)
    local self = {}
    self.source    = source
    self.citizenid = row.citizenid
    self.license   = row.license
    self.charinfo  = {
        firstname = row.firstname,
        lastname  = row.lastname,
        dob       = row.dob,
        sex       = row.sex,
    }
    self.name      = ('%s %s'):format(row.firstname, row.lastname)
    self.money     = { cash = row.cash, bank = row.bank }
    self.job       = { name = row.job, grade = row.job_grade }
    self.gang      = { name = row.gang, grade = row.gang_grade }
    self.position   = VCore.DB.AsTable(row.position)
    self.metadata   = VCore.DB.AsTable(row.metadata)
    self.inventory  = VCore.DB.AsTable(row.inventory)
    self.appearance = VCore.DB.AsTable(row.appearance)

    -- ── Money ──────────────────────────────────────────────
    function self.GetMoney(account)
        return self.money[account]
    end

    function self.SyncMoney(account, reason)
        TriggerClientEvent('v-core:client:money', self.source, self.money, account, reason)
        TriggerEvent('v-core:server:onMoneyChange', self.source, account, self.money[account], reason)
    end

    function self.AddMoney(account, amount, reason)
        amount = math.floor(tonumber(amount) or 0)
        if not self.money[account] or amount <= 0 then return false end
        self.money[account] = self.money[account] + amount
        self.SyncMoney(account, reason)
        return true
    end

    function self.RemoveMoney(account, amount, reason)
        amount = math.floor(tonumber(amount) or 0)
        if not self.money[account] or amount <= 0 then return false end
        if self.money[account] < amount then return false end
        self.money[account] = self.money[account] - amount
        self.SyncMoney(account, reason)
        return true
    end

    -- ── Job / gang ─────────────────────────────────────────
    function self.SetJob(name, grade)
        self.job = { name = name, grade = grade or 0 }
        TriggerClientEvent('v-core:client:job', self.source, self.job)
        TriggerEvent('v-core:server:onJobChange', self.source, self.job)
    end

    function self.SetGang(name, grade)
        self.gang = { name = name, grade = grade or 0 }
        TriggerClientEvent('v-core:client:gang', self.source, self.gang)
    end

    -- ── Metadata ───────────────────────────────────────────
    function self.SetMetadata(key, value)
        self.metadata[key] = value
    end

    function self.GetMetadata(key)
        return self.metadata[key]
    end

    -- ── Inventory (owned by v-inventory; these keep v-core the source of truth for saving) ──
    function self.GetInventory()
        return self.inventory
    end

    function self.SetInventory(items)
        self.inventory = items or {}
    end

    -- ── Permissions ────────────────────────────────────────
    self.permission = 'user'   -- set by the loader from the users table

    function self.HasPermission(needed)
        return VCore.HasPermission(self.source, needed)
    end

    -- ── Persistence ────────────────────────────────────────
    --- Snapshot the current server position before saving.
    function self.UpdatePosition()
        local ped = GetPlayerPed(self.source)
        if ped and ped ~= 0 then
            local c = GetEntityCoords(ped)
            self.position = { x = c.x, y = c.y, z = c.z, h = GetEntityHeading(ped) }
        end
    end

    function self.Save()
        self.UpdatePosition()
        VCore.DB.SaveCharacter(self)
    end

    --- Data sent to the client on load / refresh (no server-only fields).
    function self.ExportData()
        return {
            citizenid  = self.citizenid,
            name       = self.name,
            charinfo   = self.charinfo,
            money      = self.money,
            job        = self.job,
            gang       = self.gang,
            metadata   = self.metadata,
            permission = self.permission,
            appearance = self.appearance,
            position   = self.position,
        }
    end

    return self
end
