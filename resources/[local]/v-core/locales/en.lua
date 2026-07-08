-- v-core | English strings
Locales.en = Locales.en or {}
local T = {
    ['core.welcome']     = 'Welcome to %s, %s!',
    ['core.no_license']  = 'No license identifier found.',
    ['hud.cash']         = 'Cash',
    ['hud.bank']         = 'Bank',
    ['hud.health']       = 'Health',
    ['hud.armor']        = 'Armor',
    ['hud.hunger']       = 'Hunger',
    ['hud.thirst']       = 'Thirst',
    ['hud.stress']       = 'Stress',
    ['hud.stamina']      = 'Stamina',
    ['hud.oxygen']       = 'Oxygen',
    ['hud.money']        = 'Money',
}
for k, v in pairs(T) do Locales.en[k] = v end
