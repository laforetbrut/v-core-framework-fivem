-- v-hud | server/settings.lua
-- This module is client-side, but settings must be REGISTERED server-side (v-core owns the
-- store and the admin panel talks to the server). The values are mirrored to clients
-- automatically, so the client reads them with Core.GetSetting(...).
CreateThread(function()
    -- This module may be ensured BEFORE v-core (v-notify has to be: Core.Notify needs it),
    -- so the core is grabbed inside the thread, once the resource is actually up.
    while GetResourceState('v-core') ~= 'started' do Wait(100) end
    Wait(2600)
    local Core = exports['v-core']:GetCore()
    Core.RegisterModule('v-hud', {
        label = 'HUD', category = 'gameplay',
        settings = {

        { key = 'showMoney',  label = 'Show money',        type = 'bool',   default = true },
        { key = 'showVitals', label = 'Show vitals',       type = 'bool',   default = true },
        { key = 'lowVital',   label = 'Low-vital warning below (%)', type = 'number', default = 25, min = 0, max = 100, step = 1 },
        { key = 'showVehicle', label = 'Show the vehicle cluster', type = 'bool', default = true },
        { key = 'speedUnit',  label = 'Speed unit', type = 'select', default = 'kmh',
          options = { { value = 'kmh', label = 'km/h' }, { value = 'mph', label = 'mph' } } },
        { key = 'lowFuel',    label = 'Low-fuel warning below (%)', type = 'number', default = 15, min = 0, max = 100, step = 1 },
        },
    })
end)
