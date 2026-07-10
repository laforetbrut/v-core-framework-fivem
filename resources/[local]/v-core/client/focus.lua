-- v-core | client NUI-focus manager
-- Menus MUST take/release focus through these exports (not raw SetNuiFocus) so
-- the HUD and any other resource can observe "a menu is open" via the shared
-- statebag LocalPlayer.state.nuiOpen. Reference-counted -> safe with several
-- menus open at once, and self-healing if a menu resource stops while focused.
--   exports['v-core']:OpenMenu()                 -- cursor + input focus
--   exports['v-core']:OpenMenu(name, cursor, input)
--   exports['v-core']:CloseMenu()                -- release
local openMenus = {}

local function recount()
    local n = 0
    for _ in pairs(openMenus) do n = n + 1 end
    LocalPlayer.state:set('nuiOpen', n > 0, true)
    return n
end

exports('OpenMenu', function(name, cursor, input)
    name = name or GetInvokingResource() or 'menu'
    openMenus[name] = true
    recount()
    SetNuiFocus(cursor ~= false, input ~= false)
end)

exports('CloseMenu', function(name)
    name = name or GetInvokingResource() or 'menu'
    openMenus[name] = nil
    if recount() == 0 then SetNuiFocus(false, false) end
end)

-- Release focus if a menu resource stops while it still holds focus.
AddEventHandler('onClientResourceStop', function(res)
    if openMenus[res] then
        openMenus[res] = nil
        if recount() == 0 then SetNuiFocus(false, false) end
    end
end)
