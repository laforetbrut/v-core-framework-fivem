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
        settings = {

        { key = 'postSpawnHold', label = 'Hold black screen after spawn (ms)', type = 'number', default = 3000, min = 0, max = 15000, step = 1 },
        },
    })
end)
