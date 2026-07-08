-- v-notify | client
-- Themed toast notifications. Used by v-core Core.Notify and any module:
--   exports['v-notify']:show({ type = 'success', title = 'Bank', message = '...', duration = 4000 })

local function show(data)
    if type(data) ~= 'table' then data = { message = tostring(data) } end
    SendNUIMessage({
        action   = 'notify',
        type     = data.type or 'info',        -- info | success | error | warning
        title    = data.title or false,
        message  = data.message or '',
        duration = data.duration or 4000,
    })
end

exports('show', show)

RegisterNetEvent('v-notify:show', function(data)
    show(data)
end)
