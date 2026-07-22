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
--
-- ── SetNuiFocusKeepInput is NOT scoped, and that was a real bug ──
--
-- Unlike SetNuiFocus, SET_NUI_FOCUS_KEEP_INPUT sets a single PROCESS-WIDE flag,
-- and SetNuiFocus(false, false) does not clear it. One resource turning it on
-- therefore leaks game input into every page opened afterwards, for the rest of
-- the session.
--
-- The symptom is unmistakable once you have seen it: typing "fume" into a phone
-- message presses F, and the player climbs into a nearby car mid-sentence.
--
-- Only the interaction eye wants it on (so you can still walk while the menu is
-- up). Everything else wants it off, and "wants it off" has to be ASSERTED
-- rather than assumed, because the flag arrives in whatever state the last
-- menu left it. MenuOpened is the one call every page already makes, so the
-- assertion lives here where it cannot be forgotten.
local openMenus = {}

local function recount()
    local n = 0
    for _ in pairs(openMenus) do n = n + 1 end
    LocalPlayer.state:set('nuiOpen', n > 0, true)
    return n
end

--- keepInput: pass true ONLY if the page deliberately wants game input to keep
--- flowing (the interaction eye does, so the player can walk). Anything with a
--- text field must leave it false, which is the default.
exports('MenuOpened', function(name, keepInput)
    name = name or GetInvokingResource() or 'menu'
    openMenus[name] = true
    SetNuiFocusKeepInput(keepInput == true)
    recount()
end)

exports('MenuClosed', function(name)
    name = name or GetInvokingResource() or 'menu'
    openMenus[name] = nil
    -- Reset on the way out too: a menu that closes must not leave the next one
    -- inheriting its input policy.
    if next(openMenus) == nil then SetNuiFocusKeepInput(false) end
    recount()
end)

exports('IsAnyMenuOpen', function() return next(openMenus) ~= nil end)

-- Clear bookkeeping if a menu resource stops while still registered. Its frame
-- dies with it, so there is nothing to blur from here.
AddEventHandler('onClientResourceStop', function(res)
    if openMenus[res] then
        openMenus[res] = nil
        if next(openMenus) == nil then SetNuiFocusKeepInput(false) end
        recount()
    end
end)
