-- v-hud | server/settings.lua
-- This module is client-side, but settings must be REGISTERED server-side (v-core owns the
-- store and the admin panel talks to the server). The values are mirrored to clients
-- automatically, so the client reads them with Core.GetSetting(...).
local Core = exports['v-core']:GetCore()

CreateThread(function()
    Wait(2600)
    Core.RegisterModule('v-hud', {
        label = 'HUD', category = 'gameplay',
        settings = {

        { key = 'showMoney',  label = 'Show money',        type = 'bool',   default = true },
        { key = 'showVitals', label = 'Show vitals',       type = 'bool',   default = true },
        { key = 'lowVital',   label = 'Low-vital warning below (%)', type = 'number', default = 25, min = 0, max = 100, step = 1 },
        },
    })
end)
