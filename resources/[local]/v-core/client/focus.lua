-- v-core | client NUI-focus bookkeeping
--
-- SET_NUI_FOCUS is scoped to the CALLING resource: the native looks up the
-- caller's own ResourceUI, bails out when it has no frame, and posts
-- focusFrame/blurFrame for `resource->GetName()`
-- (code/components/nui-resources/src/ResourceUIScripting.cpp).
-- v-core declares no ui_page, so a SetNuiFocus() call made here is a silent
-- no-op and can never hand focus to another resource's page.
--
-- Therefore: the resource that owns the NUI page calls SetNuiFocus itself and
-- reports the transition here, so the HUD (and anything else) can observe
-- "a menu is open" through the shared statebag LocalPlayer.state.nuiOpen.
-- Reference-counted -> safe with several menus open, self-healing if a menu
-- resource stops while it is still registered.
--
--   -- in the resource that owns the NUI page:
--   SetNuiFocus(true, true)
--   exports['v-core']:MenuOpened()
--   ...
--   SetNuiFocus(false, false)
--   exports['v-core']:MenuClosed()
local openMenus = {}

local function recount()
    local n = 0
    for _ in pairs(openMenus) do n = n + 1 end
    LocalPlayer.state:set('nuiOpen', n > 0, true)
    return n
end

exports('MenuOpened', function(name)
    name = name or GetInvokingResource() or 'menu'
    openMenus[name] = true
    recount()
end)

exports('MenuClosed', function(name)
    name = name or GetInvokingResource() or 'menu'
    openMenus[name] = nil
    recount()
end)

exports('IsAnyMenuOpen', function() return next(openMenus) ~= nil end)

-- Clear bookkeeping if a menu resource stops while still registered. Its frame
-- dies with it, so there is nothing to blur from here.
AddEventHandler('onClientResourceStop', function(res)
    if openMenus[res] then
        openMenus[res] = nil
        recount()
    end
end)
