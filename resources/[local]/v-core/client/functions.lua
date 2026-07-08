-- v-core | client functions
VCore = VCore or {}

--- Show a notification. For now this uses the native feed; the v-ui NUI
--- notification layer can override this later without touching callers.
function VCore.Notify(message, _kind, _duration)
    SetNotificationTextEntry('STRING')
    AddTextComponentSubstringPlayerName(tostring(message))
    DrawNotification(false, true)
end
