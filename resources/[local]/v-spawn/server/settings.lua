-- v-spawn | server/settings.lua
-- This module is client-side, but settings must be REGISTERED server-side (v-core owns the
-- store and the admin panel talks to the server). The values are mirrored to clients
-- automatically, so the client reads them with Core.GetSetting(...).
CreateThread(function()
    -- This module may be ensured BEFORE v-core (v-notify has to be: Core.Notify needs it),
    -- so the core is grabbed inside the thread, once the resource is actually up.
    while GetResourceState('v-core') ~= 'started' do Wait(100) end
    local Core = exports['v-core']:GetCore()
    Core.RegisterModule('v-spawn', {
        label = 'Spawn & creation', category = 'gameplay',
        -- No settings. `postSpawnHold` was declared here and read by nothing, and it could
        -- not have been honoured anyway: client/main.lua holds the screen black only inside
        -- each flow, because a hold around the first spawn deadlocks it into a black screen
        -- that never lifts - the note at the top of that file explains why. The module stays
        -- registered so the panel lists it with its label rather than only as a manifest flag.
        settings = {},
    })
end)
