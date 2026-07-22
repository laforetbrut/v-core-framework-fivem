-- v-target | English
Locales.en = Locales.en or {}
local T = {
    -- ── What the eye is pointed at (panel title) ──
    ['tgt.lbl_player']    = 'Player',
    ['tgt.lbl_ped']       = 'Pedestrian',
    ['tgt.lbl_vehicle']   = 'Vehicle',
    ['tgt.lbl_object']    = 'Object',
    ['tgt.self']          = 'Yourself',
    ['tgt.action']        = 'Action',

    -- ── Footer key hints ──
    ['tgt.hint_nav']      = 'move',
    ['tgt.hint_pick']     = 'select',
    ['tgt.hint_close']    = 'close',

    -- ── Self ──
    ['tgt.self_inv']          = 'Inventory',
    ['tgt.self_hands']        = 'Hands up',
    ['tgt.self_vehicle']      = 'Vehicle controls',
    ['tgt.self_work']         = 'Work',
    ['tgt.self_comms']        = 'Communications',
    ['tgt.self_leave_house']  = 'Leave the property',
    ['tgt.self_house_stash']  = 'Property storage',
    ['tgt.self_admin']        = 'Admin panel',

    ['tgt.veh_engine']    = 'Engine on / off',
    ['tgt.veh_left']      = 'Left indicator',
    ['tgt.veh_right']     = 'Right indicator',
    ['tgt.veh_haz']       = 'Hazard lights',
    ['tgt.veh_seat']      = 'Change seat',
    ['tgt.veh_belt']      = 'Seatbelt',
    ['tgt.veh_lock']      = 'Lock / unlock',

    ['tgt.work_boss']     = 'Company management',
    ['tgt.work_police']   = 'Police terminal',
    ['tgt.comms_radio']   = 'Radio',
    ['tgt.comms_music']   = 'Music',

    -- ── Vehicles ──
    ['tgt.trunk']         = 'Open the boot',
    ['tgt.glovebox']      = 'Open the glovebox',
    ['tgt.doors']         = 'Open / close the doors',
    ['tgt.door_one']      = 'Open / close this door',
    ['tgt.hood']          = 'Open / close the bonnet',
    ['tgt.boot']          = 'Open / close the boot lid',
    ['tgt.engine']        = 'Engine on / off',
    ['tgt.enter_seat']    = 'Get in',
    ['tgt.lock']          = 'Lock / unlock',
    ['tgt.lockpick']      = 'Force the lock',
    ['tgt.flip']          = 'Turn it back over',
    ['tgt.diagnose']      = 'Diagnose',
    ['tgt.impound']       = 'Impound',
    ['tgt.repair']        = 'Repair',
    ['tgt.clean']         = 'Clean',

    -- ── People ──
    ['tgt.frisk']         = 'Search',
    ['tgt.police']        = 'Police',
    ['tgt.police_search'] = 'Police search',
    ['tgt.pol_cuff']      = 'Cuff / uncuff',
    ['tgt.pol_escort']    = 'Escort',
    ['tgt.pol_search']    = 'Search the suspect',

    -- ── Admin ──
    ['tgt.a_player']      = 'Moderation',
    ['tgt.a_vehicle']     = 'Moderation',
    ['tgt.a_heal']        = 'Heal',
    ['tgt.a_freeze']      = 'Freeze',
    ['tgt.a_unfreeze']    = 'Unfreeze',
    ['tgt.a_bring']       = 'Bring here',
    ['tgt.a_goto']        = 'Teleport to',
    ['tgt.a_spectate']    = 'Spectate',
    ['tgt.a_inv']         = 'Open inventory',
    ['tgt.a_unlock']      = 'Force unlock',
    ['tgt.a_plate']       = 'Read the plate',
    ['tgt.a_ped_del']     = 'Delete this ped',

    -- ── Registered by other modules ──
    ['tgt.shop']          = 'Browse the shop',
    ['tgt.vending']       = 'Vending machine',
    ['tgt.dealer']        = 'Talk to the dealer',
    ['tgt.launder']       = 'Launder money',
    ['tgt.scrap']         = 'Sell materials',
    ['tgt.cityhall']      = 'Job centre',

    -- ── Why an action is refused ──
    -- Shown under a greyed row, so each one has to say what would fix it.
    ['tgt.need_item']     = 'You are missing the right tool',
    ['tgt.err_x']         = 'Not possible right now',
    ['tgt.err_denied']    = 'Refused',
    ['tgt.err_notnet']    = 'This vehicle is not synchronised yet',
    ['tgt.err_locked']    = 'It is locked',
    ['tgt.err_unlocked']  = 'It is already unlocked',
    ['tgt.err_occupied']  = 'That seat is taken',
    ['tgt.err_notcop']    = 'Police only',
    ['tgt.err_far']       = 'Too far away',
    ['tgt.err_noitem']    = 'You are missing the right tool',
    ['tgt.err_notcuffed'] = 'They have to be cuffed first',
    ['tgt.err_novehicle'] = 'No vehicle there',
    ['tgt.err_unknown']   = 'This vehicle is not on record',
    ['tgt.err_off']       = 'Disabled on this server',
}
for k, v in pairs(T) do Locales.en[k] = v end
