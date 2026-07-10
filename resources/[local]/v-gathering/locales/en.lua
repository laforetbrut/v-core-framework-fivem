-- v-gathering | English
Locales.en = Locales.en or {}
local T = {
    ['gather.working']  = 'Harvesting… hold still',
    ['gather.canceled'] = 'Harvest cancelled.',
    ['gather.full']     = 'Your inventory is full.',
}
for k, v in pairs(T) do Locales.en[k] = v end
