-- v-music | English
Locales.en = Locales.en or {}
local T = {
    ['mus.title']    = 'Music',
    ['mus.boombox']  = 'Boombox',
    ['mus.vehicle']  = 'Car stereo',
    ['mus.jukebox']  = 'Jukebox',
    ['mus.playing']  = 'Playing',
    ['mus.play']     = 'Play',
    ['mus.pause']    = 'Pause',
    ['mus.resume']   = 'Resume',
    ['mus.stop']     = 'Stop',
    ['mus.url']      = 'Paste a link',
    ['mus.none']     = 'Nothing playing.',
    ['mus.hint']     = 'Only links from hosts the server allows will play.',
    ['mus.err_off']       = 'Music is disabled on this server.',
    ['mus.err_host']      = 'That host is not allowed here.',
    ['mus.err_noitem']    = 'You have no boombox.',
    ['mus.err_toomany']   = 'You already have one out.',
    ['mus.err_novehicle'] = 'You are not in a vehicle.',
    ['mus.err_nokeys']    = 'You do not have the keys.',
    ['mus.err_nosource']  = 'Nothing to control here.',
    ['mus.err_notyours']  = 'That is not yours to control.',
    ['mus.err_far']       = 'You are too far away.',
    ['mus.err_x']         = 'Something went wrong.',
}
for k, v in pairs(T) do Locales.en[k] = v end
