-- v-shops | English
Locales.en = Locales.en or {}
local T = {
    ['shop.help']    = 'Browse shop',
    ['shop.buy']     = 'Buy',
    ['shop.cash']    = 'Cash',
    ['shop.bank']    = 'Bank',
    ['shop.total']   = 'Total',
    ['shop.each']    = 'each',
    ['shop.bought']  = 'Bought %sx %s for $%s.',
    ['shop.nofunds'] = 'Not enough money.',
    ['shop.nospace'] = 'Not enough inventory space.',
    ['shop.blip']    = 'Store',
}
for k, v in pairs(T) do Locales.en[k] = v end
