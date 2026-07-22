-- v-radio | server
-- The device owns no data and decides no permission - v-voice does both. This file exists
-- for one reason: settings are registered server-side, so a client-only module has nothing
-- in the admin panel. Which would make "configurable in the admin panel" untrue for it.
V.Module({
    label = 'Radio device', category = 'gameplay',
    settings = {
        { key = 'presetSlots', label = 'Preset slots on the handheld', type = 'number',
          default = Config.PresetSlots, min = 1, max = 12, step = 1 },
        { key = 'clickOnJoin', label = 'Click when tuning a channel in', type = 'bool', default = true },
        { key = 'showGate',    label = 'Show which job or gang a channel belongs to', type = 'bool', default = true,
          hint = 'Off hides the padlock, so a player has to know a channel exists to look for it.' },
    },
})
