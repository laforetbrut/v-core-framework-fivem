-- v-spawn | server/settings.lua
-- This module is client-side, but settings must be REGISTERED server-side (v-core owns the
-- store and the admin panel talks to the server). The values are mirrored to clients
-- automatically, so the client reads them with Core.GetSetting(...).
local Core = exports['v-core']:GetCore()

CreateThread(function()
    Wait(2600)
    Core.RegisterModule('v-spawn', {
        label = 'Spawn & creation', category = 'gameplay',
        settings = {

        { key = 'postSpawnHold', label = 'Hold black screen after spawn (ms)', type = 'number', default = 3000, min = 0, max = 15000, step = 1 },
        },
    })
end)
