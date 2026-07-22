-- v-world | English
Locales.en = Locales.en or {}
local T = {
    ['world.saved']   = 'Saved.',
    ['world.deleted'] = 'Deleted.',
    ['world.denied']  = 'Not allowed.',
}
for k, v in pairs(T) do Locales.en[k] = v end
