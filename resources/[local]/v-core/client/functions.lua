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
