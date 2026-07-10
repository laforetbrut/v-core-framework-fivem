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
    ['shop.sold']    = 'Sold %sx %s for $%s.',
    ['shop.sell']    = 'Sell',
    ['shop.buy_mode']  = 'Buy',
    ['shop.sell_mode'] = 'Sell',
    ['shop.nothing_sell'] = 'Nothing to sell here.',
    ['shop.owned']   = 'owned',
    ['shop.nofunds'] = 'Not enough money.',
    ['shop.nospace'] = 'Not enough inventory space.',
    ['shop.too_far'] = 'You are too far from the store.',
    ['shop.no_job']  = 'This store is restricted to a job.',
    ['shop.blip']    = 'Store',
    ['shop.inventory'] = 'Inventory',
    ['shop.drag_hint'] = 'Drag an item here to buy it',
}
for k, v in pairs(T) do Locales.en[k] = v end
