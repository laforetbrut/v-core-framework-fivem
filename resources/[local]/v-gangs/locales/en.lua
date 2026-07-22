-- v-gangs | English
Locales.en = Locales.en or {}
local T = {
    ['gang.turf']      = 'Territory',
    ['gang.nobody']    = 'unclaimed',
    ['gang.contested'] = 'contested',
    ['gang.taken']     = '%s is now held by %s.',
    ['gang.lost']      = 'You have lost %s.',
}
for k, v in pairs(T) do Locales.en[k] = v end
