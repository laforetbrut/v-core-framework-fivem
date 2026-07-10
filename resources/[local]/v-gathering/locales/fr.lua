-- v-gathering | Français
Locales.fr = Locales.fr or {}
local T = {
    ['gather.working']  = 'Récolte… ne bouge pas',
    ['gather.canceled'] = 'Récolte annulée.',
    ['gather.full']     = 'Ton inventaire est plein.',
}
for k, v in pairs(T) do Locales.fr[k] = v end
