-- v-vehicles | Français
Locales.fr = Locales.fr or {}
local T = {
    ['veh.nokeys']    = 'Tu n\'as pas les clés de ce véhicule.',
    ['veh.keys_got']  = 'Tu as reçu les clés de %s.',
    ['veh.keys_gone'] = 'Tes clés de %s ont été retirées.',
    ['veh.nofuel']    = 'Panne de carburant.',
    ['veh.locked']    = 'Verrouillé.',
    ['veh.unlocked']  = 'Déverrouillé.',
}
for k, v in pairs(T) do Locales.fr[k] = v end
