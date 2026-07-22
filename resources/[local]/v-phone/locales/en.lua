-- v-phone | English
Locales.en = Locales.en or {}
local T = {
    -- ── App names (home screen) ──
    ['app.phone']    = 'Phone',
    ['app.messages'] = 'Messages',
    ['app.contacts'] = 'Contacts',
    ['app.bank']     = 'Bank',
    ['app.garage']   = 'Garage',
    ['app.wallet']   = 'Wallet',
    ['app.jobs']     = 'Jobs',
    ['app.settings'] = 'Settings',
    ['app.camera']   = 'Camera',

    -- ── Shared ──
    ['ph.loading']   = 'Loading',
    ['ph.save']      = 'Save',
    ['ph.delete']    = 'Delete',
    ['ph.send']      = 'Send',
    ['ph.call']      = 'Call',
    ['ph.message']   = 'Message',
    ['ph.name']      = 'Name',
    ['ph.number']    = 'Number',
    ['ph.on']        = 'On',
    ['ph.no_app']    = 'This app has nothing to show yet',

    -- ── Messages & contacts ──
    ['ph.write']        = 'Write a message',
    ['ph.no_messages']  = 'No conversations yet',
    ['ph.no_contacts']  = 'No contacts yet',
    ['ph.contacts']     = 'Contacts',
    ['ph.new_contact']  = 'New contact',
    ['ph.new_message']  = 'New message from %s',

    -- ── Calls ──
    ['ph.incoming']     = 'Incoming call',
    ['ph.calling']      = 'Calling',
    ['ph.in_call']      = 'In call',
    ['ph.unknown']      = 'Unknown number',
    ['ph.call_noanswer'] = 'No answer',
    ['ph.call_timeout'] = 'Call ended: it ran on too long',
    ['ph.call_dropped'] = 'The other person disconnected',
    ['ph.call_hangup']  = 'Call ended',

    -- ── Bank ──
    ['ph.balance']      = 'Account balance',
    ['ph.cash']         = 'Cash',
    ['ph.history']      = 'Recent activity',
    ['ph.no_history']   = 'No activity yet',

    -- ── Garage ──
    ['ph.no_vehicles']  = 'No vehicles registered to you',
    ['ph.veh_out']      = 'Out',
    ['ph.veh_stored']   = 'Stored',
    ['ph.out']          = 'Out on the street',

    -- ── Wallet ──
    ['ph.no_licenses']  = 'No licences on record',
    ['ph.lic_held']     = 'Held',
    ['ph.lic_none']     = 'None',

    -- ── Jobs ──
    ['ph.current_job']  = 'Current job',
    ['ph.openings']     = 'Open positions',
    ['ph.no_jobs']      = 'Nothing advertised right now',
    ['ph.jobs_hint']    = 'Go to the city hall to sign on',

    -- ── Settings ──
    ['ph.my_number']    = 'My number',
    ['ph.wallpaper']    = 'Wallpaper',
    ['ph.wall_dune']    = 'Dune',
    ['ph.wall_grid']    = 'Grid',
    ['ph.wall_night']   = 'Night',
    ['ph.wall_ember']   = 'Ember',
    ['ph.dnd']          = 'Do not disturb',
    ['ph.dnd_on']       = 'Do not disturb is on',
    ['ph.dnd_off']      = 'Do not disturb is off',

    -- ── Errors ──
    ['ph.err_x']        = 'Something went wrong',
    ['ph.err_off']      = 'That is not available on this server',
    ['ph.err_nophone']  = 'You are not carrying a phone',
    ['ph.err_nonumber'] = 'No such number',
    ['ph.err_self']     = 'That is your own number',
    ['ph.err_empty']    = 'Write something first',
    ['ph.err_busy']     = 'You are already on a call',
    ['ph.err_busy_them'] = 'The line is busy',
    ['ph.err_offline']  = 'Their phone is off',
    ['ph.err_dnd']      = 'They are not taking calls',
    ['ph.err_fields']   = 'A name and a number are needed',
    ['ph.err_unknown']  = 'Unknown app',
}
for k, v in pairs(T) do Locales.en[k] = v end
