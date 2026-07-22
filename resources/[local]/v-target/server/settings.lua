-- v-target | server/settings.lua
-- This module is client-side, but settings must be REGISTERED server-side (v-core owns the
-- store and the admin panel talks to the server). The values are mirrored to clients
-- automatically, so the client reads them with Core.GetSetting(...).
local Core = exports['v-core']:GetCore()

CreateThread(function()
    Wait(2600)
    Core.RegisterModule('v-target', {
        label = 'Interaction eye', category = 'gameplay',
        settings = {

        { key = 'maxDistance', label = 'Eye reach (m)', type = 'number', default = 7.0, min = 1, max = 25 },
        },
    })
end)
