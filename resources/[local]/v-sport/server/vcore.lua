--[[
    v-sport | server/vcore.lua

    The gym in v-core's admin panel.

    Every module of this framework declares its tunables to the core, and an administrator
    edits them in game rather than in a file. v-sport arrived from outside with no such
    declaration, so it showed up in the panel - the manifest marks it as a module - with
    nothing to change.

    WHAT IS AND IS NOT HERE. config.lua is a shared script, so the client holds its own copy
    and a value written here never reaches it. Only settings the SERVER reads at the moment it
    needs them are declared below, so every one of them takes effect on the next set trained
    rather than on the next restart. The client-side half - the effects, the minigame, the
    detection - stays in the file, where changing it means a restart anyway.

    The rest of the module is untouched: this reads Config and writes Config, the same table
    the training path already reads.
]]

--- Pull the operator's values onto Config, falling back to what the file says.
local function applySettings()
    local needs = Config.Needs

    needs.enabled       = V.SettingBool('needsEnabled',   needs.enabled)
    needs.itemNutrition = V.SettingBool('itemNutrition',  needs.itemNutrition)
    needs.hunger        = V.SettingNumber('needsHunger',  needs.hunger)
    needs.thirst        = V.SettingNumber('needsThirst',  needs.thirst)
    needs.stress        = V.SettingNumber('needsStress',  needs.stress)

    Config.Allowance.enabled = V.SettingBool('allowanceEnabled', Config.Allowance.enabled)
    Config.Allowance.total   = V.SettingNumber('allowanceTotal', Config.Allowance.total)

    Config.Decay.enabled = V.SettingBool('decayEnabled', Config.Decay.enabled)

    Config.Progression.fatigue.enabled =
        V.SettingBool('fatigueEnabled', Config.Progression.fatigue.enabled)
end

V.Module({
    label = 'Sport', category = 'gameplay',
    settings = {
        { key = 'needsEnabled', label = 'Training costs hunger and thirst', type = 'bool',
          default = Config.Needs.enabled,
          hint = 'Off leaves hunger, thirst and stress entirely to the needs module.' },

        { key = 'needsHunger', label = 'Hunger per perfect set', type = 'number',
          default = Config.Needs.hunger, min = -25, max = 25,
          hint = 'Negative eats into the gauge, which is what training should do. 0 is off.' },

        { key = 'needsThirst', label = 'Thirst per perfect set', type = 'number',
          default = Config.Needs.thirst, min = -25, max = 25 },

        { key = 'needsStress', label = 'Stress per perfect set', type = 'number',
          default = Config.Needs.stress, min = -25, max = 25,
          hint = 'Negative relieves it. Stress reads the other way round: 0 is a calm character.' },

        { key = 'itemNutrition', label = 'Supplements feed and hydrate', type = 'bool',
          default = Config.Needs.itemNutrition,
          hint = 'Off makes a protein bar worth its training effect and nothing else.' },

        { key = 'allowanceEnabled', label = 'Cap gains per cycle', type = 'bool',
          default = Config.Allowance.enabled,
          hint = 'The ceiling that stops a character maxing out in one evening.' },

        { key = 'allowanceTotal', label = 'Points per cycle', type = 'number',
          default = Config.Allowance.total, min = 0, max = 200 },

        { key = 'decayEnabled', label = 'Stats decay without training', type = 'bool',
          default = Config.Decay.enabled },

        { key = 'fatigueEnabled', label = 'Tire out over a session run', type = 'bool',
          default = Config.Progression.fatigue.enabled,
          hint = 'Back-to-back sets pay less, and recover their worth after a rest.' },
    },
})

-- The commonest reason a setting looks dead is a module that read it once at boot.
V.OnSetting(function() applySettings() end)
V.Ready(applySettings)
