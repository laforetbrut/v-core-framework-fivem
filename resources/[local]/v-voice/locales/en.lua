-- v-voice | English
Locales.en = Locales.en or {}
local T = {
    ['voice.whisper']  = 'Whisper',
    ['voice.normal']   = 'Normal',
    ['voice.shout']    = 'Shout',
    ['voice.now']      = 'Voice: %s',
    ['voice.joined']   = 'Radio channel %s.',
    ['voice.left']     = 'Radio off.',
    ['voice.muted']    = 'You have been muted.',
    ['voice.err_off']       = 'The radio is disabled on this server.',
    ['voice.err_noradio']   = 'You are not carrying a radio.',
    ['voice.err_nochannel'] = 'No such channel.',
    ['voice.err_notyours']  = 'That channel is not yours to use.',
    ['voice.err_grade']     = 'Your rank does not reach that channel.',
    ['voice.err_x']         = 'Something went wrong.',
}
for k, v in pairs(T) do Locales.en[k] = v end
