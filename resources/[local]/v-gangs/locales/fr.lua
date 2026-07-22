-- v-gangs | Français
Locales.fr = Locales.fr or {}
local T = {
    ['gang.turf']      = 'Territoire',
    ['gang.nobody']    = 'sans propriétaire',
    ['gang.contested'] = 'contesté',
    ['gang.taken']     = '%s est désormais tenu par %s.',
    ['gang.lost']      = 'Vous avez perdu %s.',
}
for k, v in pairs(T) do Locales.fr[k] = v end
