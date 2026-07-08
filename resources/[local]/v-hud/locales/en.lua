-- v-hud | English
Locales.en = Locales.en or {}
local T = {
    ['hud.cash']     = 'Cash',
    ['hud.bank']     = 'Bank',
    ['set.title']    = 'Settings',
    ['set.elements'] = 'Elements',
    ['set.accent']   = 'Accent',
    ['set.opacity']  = 'Opacity',
    ['set.scale']    = 'Scale',
    ['set.dynamic']  = 'Hide vitals when full',
    ['set.reset']    = 'Reset',
    ['set.save']     = 'Save',
    ['el.health']    = 'Health',
    ['el.armor']     = 'Armor',
    ['el.hunger']    = 'Hunger',
    ['el.thirst']    = 'Thirst',
    ['el.stress']    = 'Stress',
    ['el.stamina']   = 'Stamina',
    ['el.oxygen']    = 'Oxygen',
    ['el.money']     = 'Money',
}
for k, v in pairs(T) do Locales.en[k] = v end
