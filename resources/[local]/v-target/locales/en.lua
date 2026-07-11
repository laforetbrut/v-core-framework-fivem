-- v-target | English
Locales.en = Locales.en or {}
local T = {
    ['tgt.trunk']         = 'Open trunk',
    ['tgt.glovebox']      = 'Open glovebox',
    ['tgt.repair']        = 'Repair vehicle',
    ['tgt.frisk']         = 'Frisk / search',
    ['tgt.police_search'] = 'Search suspect',
}
for k, v in pairs(T) do Locales.en[k] = v end
