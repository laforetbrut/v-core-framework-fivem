-- The server lock exports answer instead of indexing a nil global.
-- Author: vyrriox.
H.load()
local ok, err = pcall(H.exports.IsLocked, 'VR00001')
assert(ok, 'IsLocked: ' .. tostring(err))
assert(err == false, 'a plate nobody locked is unlocked')
local ok2, err2 = pcall(H.exports.SetLocked, 'VR00001 ', true)
assert(ok2 and err2 == true, 'SetLocked: ' .. tostring(err2))
assert(H.exports.IsLocked('VR00001') == true, 'the lock holds, padding trimmed')
assert(H.client[#H.client].name == 'v-vehicles:client:locks', 'clients are told')
print('PASS locks')
