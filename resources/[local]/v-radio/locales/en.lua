-- v-radio | English
Locales.en = Locales.en or {}
local T = {
    ['radio.title']     = 'Radio',
    ['radio.sub']       = 'Monitoring',
    ['radio.available'] = 'Available channels',
    ['radio.presets']   = 'Presets',
    ['radio.listening'] = 'listening',
    ['radio.talking']   = 'talk here',
    ['radio.talkon']    = 'Talk on this',
    ['radio.leave']     = 'Leave',
    ['radio.leaveall']  = 'Turn off',
    ['radio.save']      = 'Save here',
    ['radio.empty']     = 'empty',
    ['radio.none']      = 'No channel you can use.',
    ['radio.err_noradio']     = 'You are not carrying a radio.',
    ['radio.err_off']         = 'The radio is disabled on this server.',
    ['radio.err_full']        = 'This radio only monitors %s channels.',
    ['radio.err_notyours']    = 'That channel is not yours to use.',
    ['radio.err_grade']       = 'Your rank does not reach that channel.',
    ['radio.err_nochannel']   = 'No such channel.',
    ['radio.err_notlistening'] = 'You are not monitoring that channel.',
    ['radio.err_x']           = 'Something went wrong.',
}
for k, v in pairs(T) do Locales.en[k] = v end
