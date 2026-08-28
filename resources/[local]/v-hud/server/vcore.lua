--[[
    v-hud | server/vcore.lua

    The HUD in v-core's admin panel.

    The HUD is unusual among the modules here: almost everything about it is already a per
    player choice, made in its own settings menu. What is left for an operator is the server's
    side of that bargain - what staff may do to somebody else's HUD, whether players may pass
    their look around, and how often the server writes.

    WHAT IS AND IS NOT HERE. config.lua is a shared script, so the client keeps its own copy
    and a value written here never reaches it: only settings the SERVER reads at the moment it
    needs them are declared. Two deliberate absences:

      * the odometer's own switch. It is read once, behind a `ready` flag that latches on the
        first mileage read, so a change would not be seen until a restart. Its per-message
        ceiling below IS re-read, so that one is offered.

      * the HUD's stress system. v-status owns hunger, thirst and stress on this framework,
        and the HUD is a readout of them (see client/vstatus.lua). Turning its own stress
        system back on would put two systems on the same value and the same screen effects,
        which is a bug this framework already had once.
]]

local function applySettings()
    Config.Policy.allowAdminPush    = V.SettingBool('allowAdminPush',    Config.Policy.allowAdminPush)
    Config.Policy.announceAdminPush = V.SettingBool('announceAdminPush', Config.Policy.announceAdminPush)
    Config.Policy.allowSharing      = V.SettingBool('allowSharing',      Config.Policy.allowSharing)

    Config.Persistence.debounce = V.SettingNumber('saveDebounce',  Config.Persistence.debounce)
    Config.Odometer.saveEvery   = V.SettingNumber('odoSaveEvery',  Config.Odometer.saveEvery)
end

V.Module({
    label = 'Hud', category = 'gameplay',
    settings = {
        { key = 'allowAdminPush', label = 'Staff may push HUD settings', type = 'bool',
          default = Config.Policy.allowAdminPush,
          hint = 'Off refuses /hudadmin outright, whatever rank asks.' },

        { key = 'announceAdminPush', label = 'Tell the player it was pushed', type = 'bool',
          default = Config.Policy.announceAdminPush,
          hint = 'Off changes their HUD silently.' },

        { key = 'allowSharing', label = 'Players may share their look', type = 'bool',
          default = Config.Policy.allowSharing,
          hint = 'The export and import codes in the HUD menu. Applies to players who connect after the change.' },

        { key = 'saveDebounce', label = 'Settings save delay (ms)', type = 'number',
          default = Config.Persistence.debounce, min = 250, max = 30000, step = 250,
          hint = 'How long a run of changes is allowed to settle before one write. Higher is fewer writes.' },

        { key = 'odoSaveEvery', label = 'Odometer metres per report', type = 'number',
          default = Config.Odometer.saveEvery, min = 100, max = 10000, step = 100,
          hint = 'Also sets the ceiling on a single mileage report, so a client cannot claim more.' },
    },
})

-- Re-read on every change: a module that caches a setting at boot is the usual reason one
-- looks dead in the panel.
V.OnSetting(function() applySettings() end)
V.Ready(applySettings)
