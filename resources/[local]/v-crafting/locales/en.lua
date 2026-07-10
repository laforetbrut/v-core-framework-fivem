-- v-crafting | English
Locales.en = Locales.en or {}
local T = {
    ['craft.help']    = 'Craft',
    ['craft.sub']     = 'Select a recipe · you need every material to craft',
    ['craft.make']    = 'Craft',
    ['craft.done']    = 'Crafted %sx %s.',
    ['craft.missing'] = 'Missing materials.',
    ['craft.nospace'] = 'Not enough inventory space.',
    ['craft.too_far'] = 'Move closer to the bench.',
    ['craft.locked']  = 'You cannot craft this here.',
}
for k, v in pairs(T) do Locales.en[k] = v end
