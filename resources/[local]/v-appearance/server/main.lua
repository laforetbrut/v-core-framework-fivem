-- v-appearance | server
-- Thin server surface over v-core's appearance persistence, plus push-to-client
-- re-apply helpers. All ped natives are client-side, so the server never renders;
-- it only reads/writes the stored appearance and asks a client to re-apply.
local Core = exports['v-core']:GetCore()

--- Current stored appearance for a source (or nil).
exports('GetAppearance', function(src)
    local p = Core.GetPlayer(src)
    return p and p.appearance or nil
end)

--- Persist an appearance for a source and keep the live object in sync.
exports('SaveAppearance', function(src, appearance)
    local p = Core.GetPlayer(src)
    if not p then return false end
    p.appearance = appearance or {}
    Core.DB.SaveAppearance(p.citizenid, p.appearance)
    return true
end)

--- Ask a client to re-apply its full stored appearance (after an admin edit, etc.).
exports('ApplyTo', function(src)
    local p = Core.GetPlayer(src)
    if not p then return false end
    TriggerClientEvent('v-appearance:client:apply', src, p.appearance or {})
    return true
end)

--- Push a single-slot re-apply to a client (used by clothing equip/unequip).
exports('ApplyRefTo', function(src, kind, compId, ref)
    TriggerClientEvent('v-appearance:client:applyRef', src, kind, compId, ref)
end)

-- ══════════════════════════════════════════════════════════════════
--  Admin-tunable settings (v-core module registry)
-- ══════════════════════════════════════════════════════════════════
-- Declared to v-core, which stores the values and serves them to the admin panel.
-- Applied back onto Config so the existing code paths see an operator's change without
-- a restart. See DEVELOPERS.md.
local function declareSettings()
    Core.RegisterModule('v-appearance', {
        label = 'Appearance', category = 'gameplay',
        settings = {

            { key = 'distance',      label = 'Salon range (m)',   type = 'number', default = Config.Distance, min = 0.5, max = 10 },
            { key = 'heightEnabled', label = 'Height (experimental)', type = 'bool', default = Config.Height.enabled,
              hint = 'GTA V has no ped-scale native; this is visual only and glitches.' },
        },
    })
end

local function S(key, fallback) return Core.GetSetting('v-appearance', key, fallback) end

local function applySettings()

    Config.Distance       = S('distance', Config.Distance)
    Config.Height.enabled = S('heightEnabled', Config.Height.enabled)
end

AddEventHandler('v-core:server:settingChanged', function(mod)
    if mod == 'v-appearance' then applySettings() end
end)

V.Ready(function()
    declareSettings()
    applySettings()
end)
