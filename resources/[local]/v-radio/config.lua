-- v-radio | shared config
-- The device. `v-voice` is the transport and owns every permission decision; this module
-- owns the object in your hand, its presets and its mix.
--
-- Channels themselves live in `world_radio` (owned by v-world) and are edited from the
-- admin panel -> Editor -> Radio channels. Nothing about who may use them is decided here.
Config = {}

-- F3 opens the handheld. Push-to-talk stays on v-voice's key: one radio, one talk button.
Config.Key = 'F3'

-- Preset slots on the device. Six is what fits a keypad without a scroll bar.
Config.PresetSlots = 6
