-- v-target | English
Locales.en = Locales.en or {}
local T = {
    ['tgt.trunk']         = 'Open trunk',
    ['tgt.glovebox']      = 'Open glovebox',
    ['tgt.doors']         = 'Open / close doors',
    ['tgt.hood']          = 'Open / close hood',
    ['tgt.boot']          = 'Open / close boot',
    ['tgt.engine']        = 'Toggle engine',
    ['tgt.lock']          = 'Lock / unlock',
    ['tgt.flip']          = 'Flip vehicle',
    ['tgt.repair']        = 'Repair vehicle',
    ['tgt.clean']         = 'Clean vehicle',
    ['tgt.frisk']         = 'Frisk / search',
    ['tgt.police_search'] = 'Search suspect',
    ['tgt.a_heal']        = 'Heal (admin)',
    ['tgt.a_freeze']      = 'Freeze (admin)',
    ['tgt.a_unfreeze']    = 'Unfreeze (admin)',
    ['tgt.a_bring']       = 'Bring here (admin)',
    ['tgt.a_goto']        = 'Teleport to (admin)',
    ['tgt.a_spectate']    = 'Spectate (admin)',
    ['tgt.a_inv']         = 'Open inventory (admin)',
}
for k, v in pairs(T) do Locales.en[k] = v end
