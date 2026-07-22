-- v-housing | English
Locales.en = Locales.en or {}
local T = {
    ['house.blip']      = 'Property',
    ['house.door']      = 'Door',
    ['house.leave']     = 'Leave',
    ['house.stash']     = 'Storage',
    ['house.inside']    = 'You are inside.',
    ['house.bought']    = 'Bought for $%s.',
    ['house.rented']    = 'Rented for $%s.',
    ['house.rent_paid'] = 'Rent paid: $%s.',
    ['house.got_key']   = 'You have been given a key.',
    ['house.err_off']       = 'Property is disabled on this server.',
    ['house.err_noprop']    = 'No property here.',
    ['house.err_far']       = 'You are too far from the door.',
    ['house.err_taken']     = 'Somebody already lives here.',
    ['house.err_toomany']   = 'You already hold as many properties as you may.',
    ['house.err_funds']     = 'You cannot afford it.',
    ['house.err_notyours']  = 'This is not yours.',
    ['house.err_nokey']     = 'You do not have a key.',
    ['house.err_locked']    = 'The lock has been changed: the rent is overdue.',
    ['house.err_notinside'] = 'You are not inside a property.',
    ['house.err_notarget']  = 'Nobody there.',
    ['house.err_x']         = 'Something went wrong.',
}
for k, v in pairs(T) do Locales.en[k] = v end
