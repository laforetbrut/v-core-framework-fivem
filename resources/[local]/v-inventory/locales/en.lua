-- v-inventory | English
Locales.en = Locales.en or {}
local T = {
    ['inv.title']      = 'Inventory',
    ['inv.weight']     = 'Weight',
    ['inv.use']        = 'Use',
    ['inv.give']       = 'Give',
    ['inv.drop']       = 'Drop',
    ['inv.amount']     = 'Amount',
    ['inv.confirm']    = 'Confirm',
    ['inv.cancel']     = 'Cancel',
    ['inv.trunk']      = 'Trunk',
    ['inv.glovebox']   = 'Glovebox',
    ['inv.stash']      = 'Stash',
    ['inv.ground']     = 'Ground',
    ['inv.empty']      = 'Empty',
    ['inv.full']       = 'Not enough space.',
    ['inv.no_target']  = 'No one nearby.',
    ['inv.gave']       = 'Gave %sx %s.',
    ['inv.received']   = 'Received %sx %s.',
    ['inv.used']       = 'Used %s.',
    ['inv.help_trunk'] = 'Open trunk',
}
for k, v in pairs(T) do Locales.en[k] = v end
