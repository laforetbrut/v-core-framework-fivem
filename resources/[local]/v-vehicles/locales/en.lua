-- v-vehicles | English
Locales.en = Locales.en or {}
local T = {
    ['veh.nokeys']    = 'You do not have the keys to this vehicle.',
    ['veh.keys_got']  = 'You received the keys to %s.',
    ['veh.keys_gone'] = 'Your keys to %s were revoked.',
    ['veh.nofuel']    = 'Out of fuel.',
    ['veh.belt_on'] = 'Seatbelt fastened.',
    ['veh.belt_off'] = 'Seatbelt unfastened.',
    ['veh.belt_ejected'] = 'You went through the windscreen.',
    ['veh.locked']    = 'Locked.',
    ['veh.unlocked']  = 'Unlocked.',
}
for k, v in pairs(T) do Locales.en[k] = v end
