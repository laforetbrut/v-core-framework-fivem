-- v-core | client functions
VCore = VCore or {}

--- Show a notification via v-notify (themed toast), falling back to the
--- native feed if v-notify isn't running.
function VCore.Notify(message, kind, duration)
    local ok = pcall(function()
        exports['v-notify']:show({ type = kind or 'info', message = message, duration = duration })
    end)
    if not ok then
        SetNotificationTextEntry('STRING')
        AddTextComponentSubstringPlayerName(tostring(message))
        DrawNotification(false, true)
    end
end

-- ── Live settings mirror ───────────────────────────────────────
-- The server pushes every setting change to every client. A client-side module reads its
-- own tunables from here instead of inventing a per-module net event, and third-party
-- scripts get the same for free.
VCore.Settings = VCore.Settings or {}

RegisterNetEvent('v-core:client:settingChanged', function(module, key, value)
    if type(module) ~= 'string' or type(key) ~= 'string' then return end
    VCore.Settings[module] = VCore.Settings[module] or {}
    VCore.Settings[module][key] = value
    TriggerEvent('v-core:client:onSettingChanged', module, key, value)
end)

--- Read a mirrored setting. `fallback` is returned until the server has pushed one, so a
--- client module still behaves before the first change of the session.
function VCore.GetSetting(module, key, fallback)
    local m = VCore.Settings[module]
    local v = m and m[key]
    if v ~= nil then return v end
    return fallback
end
