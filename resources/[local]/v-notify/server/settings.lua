-- v-notify | server/settings.lua
-- This module is client-side, but settings must be REGISTERED server-side (v-core owns the
-- store and the admin panel talks to the server). The values are mirrored to clients
-- automatically, so the client reads them with Core.GetSetting(...).
CreateThread(function()
    -- This module may be ensured BEFORE v-core (v-notify has to be: Core.Notify needs it),
    -- so the core is grabbed inside the thread, once the resource is actually up.
    while GetResourceState('v-core') ~= 'started' do Wait(100) end
    local Core = exports['v-core']:GetCore()
    Core.RegisterModule('v-notify', {
        label = 'Notifications', category = 'gameplay',
        settings = {

        { key = 'duration', label = 'Default duration (ms)', type = 'number', default = 4000, min = 500, max = 20000, step = 1 },
        { key = 'maxStack', label = 'Max toasts on screen',  type = 'number', default = 4, min = 1, max = 12, step = 1 },
        },
    })
end)
