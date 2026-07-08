-- v-core | database layer (oxmysql)
-- All SQL access goes through here so the rest of the core never touches raw queries.
VCore = VCore or {}
VCore.DB = {}

--- Coerce an oxmysql JSON/text column into a Lua table.
local function asTable(value)
    if type(value) == 'table' then return value end
    if type(value) == 'string' and value ~= '' then return json.decode(value) or {} end
    return {}
end
VCore.DB.AsTable = asTable

--- Ensure an account row exists and refresh its last_seen.
function VCore.DB.EnsureUser(license, name)
    MySQL.query.await(
        'INSERT INTO users (license, name) VALUES (?, ?) ON DUPLICATE KEY UPDATE name = ?, last_seen = CURRENT_TIMESTAMP',
        { license, name, name }
    )
end

--- Fetch the first character for a license (multi-character selection comes later).
function VCore.DB.GetCharacterByLicense(license)
    return MySQL.single.await('SELECT * FROM characters WHERE license = ? ORDER BY slot ASC LIMIT 1', { license })
end

--- Fetch a character row by citizen id.
function VCore.DB.GetCharacterByCitizenId(citizenid)
    return MySQL.single.await('SELECT * FROM characters WHERE citizenid = ?', { citizenid })
end

--- Create a default character for a license and return the fresh row.
function VCore.DB.CreateDefaultCharacter(license, name)
    local citizenid = VCore.GenerateCitizenId()
    MySQL.insert.await(
        'INSERT INTO characters (citizenid, license, firstname, lastname, cash, bank) VALUES (?, ?, ?, ?, ?, ?)',
        { citizenid, license, 'John', 'Doe', Config.StartingMoney.cash, Config.StartingMoney.bank }
    )
    return VCore.DB.GetCharacterByCitizenId(citizenid)
end

--- Persist a player object back to its character row.
function VCore.DB.SaveCharacter(player)
    MySQL.update.await(
        [[UPDATE characters SET
            cash = ?, bank = ?, job = ?, job_grade = ?, gang = ?, gang_grade = ?,
            position = ?, metadata = ?, inventory = ?
          WHERE citizenid = ?]],
        {
            player.money.cash, player.money.bank,
            player.job.name, player.job.grade,
            player.gang.name, player.gang.grade,
            json.encode(player.position or {}),
            json.encode(player.metadata or {}),
            json.encode(player.inventory or {}),
            player.citizenid,
        }
    )
end

--- Read an account's permission level.
function VCore.DB.GetUserPermission(license)
    return MySQL.scalar.await('SELECT permission FROM users WHERE license = ?', { license }) or 'user'
end

--- Persist an account's permission level.
function VCore.DB.SetUserPermission(license, level)
    MySQL.update.await('UPDATE users SET permission = ? WHERE license = ?', { level, license })
end

--- Fire-and-forget log insert (never blocks the caller).
function VCore.DB.InsertLog(category, message, data, citizenid)
    MySQL.insert('INSERT INTO logs (category, citizenid, message, data) VALUES (?, ?, ?, ?)',
        { category, citizenid, message, data and json.encode(data) or nil })
end

--- Load every item definition keyed by name (used by inventory/shops).
function VCore.DB.GetItems()
    local rows = MySQL.query.await('SELECT * FROM items') or {}
    local items = {}
    for _, row in ipairs(rows) do
        items[row.name] = row
    end
    return items
end
