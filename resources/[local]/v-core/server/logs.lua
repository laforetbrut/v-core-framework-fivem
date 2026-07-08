-- v-core | logging
-- Structured logs to console + the `logs` table. Webhook output plugs in here later.
VCore = VCore or {}

--- Record a log entry.
--- @param category string  e.g. 'economy', 'admin', 'anticheat', 'inventory'
--- @param message  string  human-readable line
--- @param data     table?  optional structured payload
--- @param citizenid string? optional owner
function VCore.Log(category, message, data, citizenid)
    if Config.Debug then
        print(('^3[log:%s]^7 %s'):format(category, message))
    end
    VCore.DB.InsertLog(category, message, data, citizenid)
end
