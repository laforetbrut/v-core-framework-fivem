-- v-core | client functions
VCore = VCore or {}

--- Show a basic notification above the minimap.
function VCore.Notify(message)
    SetNotificationTextEntry('STRING')
    AddTextComponentSubstringPlayerName(tostring(message))
    DrawNotification(false, true)
end
