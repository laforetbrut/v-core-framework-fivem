-- v-phone | server
--
-- iFruit. Numbers, contacts, messages, calls and the app registry.
--
-- **The phone is a shell.** Messages and contacts are the only things it owns; every other
-- app is a view over the module that owns the data, and those calls are made by the client
-- straight to that module. Proxying them through here would put a second copy of the
-- bank's rules in the phone, and a second copy is a second answer.
--
-- **Server-authoritative in the two places it matters.** A message is stored and relayed
-- here, because a client that could write another player's history could forge it. A call
-- is routed here, because ringing somebody must not depend on the caller knowing where
-- they are.

V.Provide('phone')

local Core
local Numbers  = {}      -- [citizenid] = number, cached for the length of a session
local Online   = {}      -- [number]    = source
local Calls    = {}      -- [callId]    = { a, b, aNum, bNum, state, at }
local CallOf   = {}      -- [source]    = callId
local Apps     = {}      -- [id]        = registry row (config seed + RegisterApp)
local WorldApps = {}     -- [id]        = the operator's row from v-world
local callSeq  = 0

local function num(v, d) return tonumber(v) or d or 0 end

local function L(src, k)
    local p = Core and Core.GetPlayer(src)
    local lang = (p and p.lang) or 'fr'
    return (Locales[lang] or Locales.fr or {})[k] or k
end

-- ══════════════════════════════════════════════════════════════
-- Settings
-- ══════════════════════════════════════════════════════════════
V.Module({
    label = 'Phone', category = 'gameplay',
    settings = {
        { key = 'enabled', label = 'Phone enabled', type = 'bool', default = true,
          hint = 'Off stops the phone opening. Numbers already minted are kept.' },

        { key = 'numberFormat', label = 'Number format', type = 'string', default = Config.NumberFormat,
          hint = 'Every # becomes a random digit; everything else is kept verbatim. Changing this only affects numbers minted afterwards, because an existing number is how other characters already reach that player.' },

        { key = 'requireItem', label = 'A phone item is required', type = 'bool', default = false,
          hint = 'On, the player must carry the `phone` item to open it. Off, everyone has one, which is the friendlier default for a young server.' },

        { key = 'maxLength', label = 'Message length limit', type = 'number', default = Config.Messages.maxLength,
          min = 20, max = 1000, step = 10 },

        { key = 'retentionDays', label = 'Keep messages for (days)', type = 'number', default = Config.Messages.retentionDays,
          min = 0, max = 365, step = 1,
          hint = 'Pruned once at boot. 0 keeps everything for ever, which is a growing table nobody trims.' },

        { key = 'ringSeconds', label = 'Ring for (s) before giving up', type = 'number', default = Config.Calls.ringSeconds,
          min = 5, max = 120, step = 1 },

        { key = 'maxMinutes', label = 'Longest call (min)', type = 'number', default = Config.Calls.maxMinutes,
          min = 1, max = 240, step = 1,
          hint = 'A ceiling so a call somebody walked away from does not hold a voice channel open all night.' },

        { key = 'anonymous', label = 'Allow withholding your number', type = 'bool', default = false,
          hint = 'On, a caller may hide their number. It is off by default because an anonymous call is a harassment tool before it is a roleplay tool.' },

        { key = 'wallpaperHosts', label = 'Wallpaper image hosts', type = 'string',
          default = table.concat(Config.WallpaperHosts, ', '),
          hint = 'Comma separated. A wallpaper link is a URL a client will fetch, so this is an operator decision. An open list is a way to make somebody load anything at all.' },

        { key = 'customWallpaper', label = 'Allow linked wallpapers', type = 'bool', default = true,
          hint = 'Off leaves only the built-in gradients, which cost nothing to load.' },

        { key = 'camera', label = 'Camera app enabled', type = 'bool', default = false,
          hint = 'The camera writes to a gallery. Uploading anywhere is an operator decision, so it has no default destination and stays off until one is set.' },

        { key = 'cameraUpload', label = 'Camera upload target (URL)', type = 'string', default = '',
          hint = 'Where a photo is posted. Empty means the photo never leaves the server, which is the safe state.' },
    },
})

local function S(key, fallback) return V.Setting(key, fallback) end

-- ══════════════════════════════════════════════════════════════
-- Numbers
-- ══════════════════════════════════════════════════════════════
--- `#` becomes a digit; everything else is kept. The format is a setting rather than code
--- because "what a phone number looks like here" is a server's decision, not ours.
local function mintNumber(format)
    return (tostring(format):gsub('#', function() return tostring(math.random(0, 9)) end))
end

--- Retried rather than trusted: two characters created in the same second would otherwise
--- collide, and a duplicate number means two people share an inbox.
local function newNumber()
    local format = tostring(S('numberFormat', Config.NumberFormat))
    for _ = 1, 40 do
        local n = mintNumber(format)
        local taken = MySQL.scalar.await('SELECT 1 FROM characters WHERE phone = ? LIMIT 1', { n })
        if not taken then return n end
    end
    return nil
end

local function numberOfCid(cid)
    if Numbers[cid] then return Numbers[cid] end
    local n = MySQL.scalar.await('SELECT phone FROM characters WHERE citizenid = ?', { cid })
    if n and n ~= '' then Numbers[cid] = n end
    return Numbers[cid]
end

local function cidOfNumber(number)
    return MySQL.scalar.await('SELECT citizenid FROM characters WHERE phone = ?', { number })
end

local function ensureNumber(src, p)
    local existing = numberOfCid(p.citizenid)
    if existing then
        Online[existing] = src
        return existing
    end
    local n = newNumber()
    if not n then
        print('[v-phone] could not mint a free number: the format has too few digits for the number of characters on this server')
        return nil
    end
    MySQL.update.await('UPDATE characters SET phone = ? WHERE citizenid = ?', { n, p.citizenid })
    Numbers[p.citizenid] = n
    Online[n] = src
    return n
end

-- ══════════════════════════════════════════════════════════════
-- Apps
-- ══════════════════════════════════════════════════════════════
--- The same bet the module registry made: a script ships its own app without touching
--- v-phone. `page` is a URL the phone iframes; a Lua-only app just omits it and handles
--- its own NUI when opened.
-- Forward declaration: `local function` is only in scope AFTER its definition, and the
-- RegisterApp export below is written before it.
local loadWorldApps

local function registerApp(id, info, owner)
    id = tostring(id or '')
    if id == '' then return false end
    Apps[id] = {
        id    = id,
        label = tostring(info.label or id),
        icon  = tostring(info.icon or 'dot'),
        page  = info.page,
        owner = owner or info.owner,
        slot  = num(info.slot, 99),
        -- Four apps sit in the dock rather than the paging grid: the ones a player
        -- reaches for without thinking should not move when the page does.
        dock  = info.dock == true,
        job   = info.job, jobGrade = info.jobGrade, gang = info.gang,
        -- A phone with no Phone app is a brick, so a few apps refuse to be removed.
        required = info.required == true,
    }
    return true
end

exports('RegisterApp', function(id, info)
    info = info or {}
    local ok = registerApp(id, info, GetInvokingResource())
    -- Give the operator a row to edit. Without one, a third-party app is visible but
    -- ungovernable: to disable or gate it they would have to guess its id and create the
    -- row by hand. INSERT IGNORE, so an operator's existing edits are never overwritten.
    if ok and GetResourceState('v-world') == 'started' and exports['v-world']:IsReady() then
        MySQL.insert.await([[INSERT IGNORE INTO world_apps (id, label, slot, job, job_grade, gang, enabled)
            VALUES (?,?,?,?,?,?,1)]],
            { tostring(id), tostring(info.label or id), num(info.slot, 99),
              info.job or '', num(info.jobGrade, 0), info.gang or '' })
        loadWorldApps()
    end
    return ok
end)

exports('UnregisterApp', function(id) Apps[tostring(id or '')] = nil end)

-- v-world owns the table; asking it rather than reading `world_apps` here keeps one
-- module responsible for the content layer, which is the whole point of having one.
function loadWorldApps()  -- assigns the forward-declared local above
    WorldApps = {}
    if GetResourceState('v-world') ~= 'started' then return end
    for _, r in ipairs(V.Use('v-world').GetPhoneApps() or {}) do WorldApps[r.id] = r end
end

--- What this specific player may see. Three gates, and they are not interchangeable:
--- the operator's enable switch, the owning module actually running, and the job/gang the
--- operator set on that row.
local function appsFor(src, p)
    local out = {}
    for id, a in pairs(Apps) do
        local w = WorldApps[id]
        local ok = true

        if w and tonumber(w.enabled) == 0 then ok = false end
        -- An app that opens onto a stopped module is worse than an app that is not there.
        if ok and a.owner and a.owner ~= 'v-phone' and GetResourceState(a.owner) ~= 'started' then ok = false end
        if ok and w and w.job and w.job ~= '' then
            ok = (p.job and p.job.name == w.job) and (num(p.job.grade, 0) >= num(w.job_grade, 0))
        end
        if ok and w and w.gang and w.gang ~= '' then
            ok = (p.gang and p.gang.name == w.gang)
        end

        if ok then
            out[#out + 1] = {
                id = id, label = a.label, icon = a.icon, page = a.page, dock = a.dock or nil,
                slot = (w and num(w.slot, a.slot)) or a.slot,
                required = a.required or nil,
            }
        end
    end
    table.sort(out, function(x, y)
        if x.slot ~= y.slot then return x.slot < y.slot end
        return x.id < y.id
    end)
    return out
end

exports('GetApps', function(src)
    local p = Core.GetPlayer(src)
    return p and appsFor(src, p) or {}
end)

-- ══════════════════════════════════════════════════════════════
-- Preferences
-- ══════════════════════════════════════════════════════════════
-- Stored in the character's metadata rather than a table of their own: it is a handful of
-- per-character values that are already persisted with everything else about them.
--- A wallpaper link is a URL a client will fetch, so the host has to be one the operator
--- allowed. Rejected rather than sanitised: quietly rewriting somebody's link into one
--- that works is worse than telling them it is not permitted.
local function wallpaperAllowed(url)
    url = tostring(url or '')
    if url == '' then return true end                      -- clearing it is always fine
    local host = url:match('^https?://([^/]+)')
    if not host then return false end
    host = host:lower():gsub(':%d+$', '')
    for _, allowed in ipairs(V.Setting('wallpaperHosts', Config.WallpaperHosts) or Config.WallpaperHosts) do
        if host == allowed or host:sub(-(#allowed + 1)) == '.' .. allowed then return true end
    end
    return false
end

local function prefsOf(p)
    local m = p.GetMetadata('phone')
    if type(m) ~= 'table' then m = {} end
    -- `glass` is iOS 27's transparency slider: 0 is ultra clear, 100 is fully tinted.
    -- It is a real stored preference driving a CSS variable, not a decorative control.
    local glass = tonumber(m.glass)
    return {
        wallpaper = tostring(m.wallpaper or Config.DefaultWallpaper),
        dnd       = m.dnd == true,
        ringtone  = tostring(m.ringtone or 'default'),
        glass     = math.max(0, math.min(100, math.floor(glass or Config.DefaultGlass))),
        -- What the player REMOVED, not what they installed. Storing the removals
        -- means a new app an operator adds later is there without every existing
        -- character having to go and find it in the store.
        removed   = (type(m.removed) == 'table') and m.removed or {},
        actionApp = m.actionApp and tostring(m.actionApp) or nil,
        -- A linked wallpaper, its fit, and the shape of the device itself.
        wallpaperUrl = m.wallpaperUrl and tostring(m.wallpaperUrl) or nil,
        wallFit   = (m.wallFit == 'contain') and 'contain' or Config.WallpaperFit,
        size      = math.max(0.75, math.min(1.15, tonumber(m.size) or Config.DeviceSize)),
        side      = (m.side == 'left') and 'left' or 'right',
        -- The home screen: the player's own order, and any folders they made.
        layout    = (type(m.layout) == 'table') and m.layout or nil,
    }
end

--- Two lists, because they answer two different questions. `available` is what the
--- OPERATOR permits this player to have; `installed` is what the PLAYER has chosen to
--- keep. The store shows the first, the home screen shows the second.
local function appsFrom(src, p)
    local available = appsFor(src, p)
    local removed = {}
    for _, id in ipairs(prefsOf(p).removed or {}) do removed[id] = true end
    local installed = {}
    for _, a in ipairs(available) do
        if not removed[a.id] or a.required then installed[#installed + 1] = a end
    end
    return available, installed
end

-- ══════════════════════════════════════════════════════════════
-- Messages
-- ══════════════════════════════════════════════════════════════
--- Conversations, newest first: for each counterpart, the last message and how many are
--- unread. Filtered to this citizen id in SQL, so a client cannot ask for somebody else's.
local function conversations(cid)
    -- Three plain queries rather than one with window functions: MariaDB only grew those
    -- in 10.2, and a phone that works on the operator's database matters more than a
    -- clever statement.
    local last = MySQL.query.await([[
        SELECT IF(from_cid = ?, to_cid, from_cid) AS other, MAX(id) AS last_id
        FROM phone_messages WHERE from_cid = ? OR to_cid = ?
        GROUP BY other
    ]], { cid, cid, cid }) or {}
    if #last == 0 then return {} end

    local unread = {}
    for _, r in ipairs(MySQL.query.await(
        'SELECT from_cid AS other, COUNT(*) AS n FROM phone_messages WHERE to_cid = ? AND seen = 0 GROUP BY from_cid',
        { cid }) or {}) do
        unread[r.other] = num(r.n, 0)
    end

    local out = {}
    for _, r in ipairs(last) do
        local m = MySQL.single.await('SELECT body, at FROM phone_messages WHERE id = ?', { r.last_id })
        out[#out + 1] = {
            other  = r.other,
            number = numberOfCid(r.other) or r.other,
            body   = m and m.body or '',
            at     = m and m.at or nil,
            unread = unread[r.other] or 0,
            lastId = r.last_id,
        }
    end
    table.sort(out, function(a, b) return (a.lastId or 0) > (b.lastId or 0) end)
    return out
end

local function conversation(cid, otherCid, limit)
    local rows = MySQL.query.await([[
        SELECT id, from_cid, body, at, seen FROM phone_messages
        WHERE (from_cid = ? AND to_cid = ?) OR (from_cid = ? AND to_cid = ?)
        ORDER BY at DESC, id DESC LIMIT ?
    ]], { cid, otherCid, otherCid, cid, limit }) or {}

    -- Read back in ascending order: the query takes the newest N, the reader wants them
    -- oldest first.
    local out = {}
    for i = #rows, 1, -1 do
        local r = rows[i]
        out[#out + 1] = { id = r.id, mine = (r.from_cid == cid), body = r.body, at = r.at }
    end
    MySQL.update('UPDATE phone_messages SET seen = 1 WHERE to_cid = ? AND from_cid = ? AND seen = 0',
        { cid, otherCid })
    return out
end

--- The one write the phone owns. Returns ok plus the stored row, or an error key.
local function sendMessage(fromCid, toNumber, body)
    body = tostring(body or ''):sub(1, math.max(1, math.floor(num(S('maxLength', Config.Messages.maxLength), 250))))
    if body:gsub('%s', '') == '' then return nil, 'empty' end

    local toCid = cidOfNumber(toNumber)
    if not toCid then return nil, 'nonumber' end
    if toCid == fromCid then return nil, 'self' end

    local id = MySQL.insert.await(
        'INSERT INTO phone_messages (from_cid, to_cid, body) VALUES (?, ?, ?)',
        { fromCid, toCid, body })

    -- Delivered live only if they are on: an offline character reads it next time they
    -- open the app, which is what the table is for.
    local target = Online[numberOfCid(toCid) or '']
    if target then
        TriggerClientEvent('v-phone:client:message', target, {
            from = numberOfCid(fromCid), fromCid = fromCid, body = body, id = id,
        })
    end
    return { id = id, body = body }, nil
end

exports('SendMessage', function(fromCid, toNumber, body)
    local row, err = sendMessage(tostring(fromCid or ''), tostring(toNumber or ''), body)
    return row ~= nil, err
end)

-- ══════════════════════════════════════════════════════════════
-- Calls
-- ══════════════════════════════════════════════════════════════
-- The phone does no audio. It decides who is on a call and tells both clients to hand
-- themselves to v-voice; v-voice owns the Mumble channel.
local function endCall(id, reason)
    local c = Calls[id]
    if not c then return end
    Calls[id] = nil
    for _, s in ipairs({ c.a, c.b }) do
        if s and CallOf[s] == id then
            CallOf[s] = nil
            TriggerClientEvent('v-phone:client:callEnd', s, reason)
        end
    end
end

local function startCall(src, p, toNumber, anonymous)
    if CallOf[src] then return nil, 'busy' end

    local toCid = cidOfNumber(toNumber)
    if not toCid then return nil, 'nonumber' end
    if toCid == p.citizenid then return nil, 'self' end

    local target = Online[toNumber]
    if not target then return nil, 'offline' end
    if CallOf[target] then return nil, 'busy_them' end

    local tp = Core.GetPlayer(target)
    if tp and prefsOf(tp).dnd then return nil, 'dnd' end

    callSeq = callSeq + 1
    local id = callSeq
    Calls[id] = {
        a = src, b = target, state = 'ringing', at = os.time(),
        aNum = numberOfCid(p.citizenid), bNum = toNumber,
        anonymous = anonymous and V.SettingBool('anonymous', false) or false,
    }
    CallOf[src], CallOf[target] = id, id

    TriggerClientEvent('v-phone:client:callOut', src, { id = id, number = toNumber })
    TriggerClientEvent('v-phone:client:callIn', target, {
        id = id,
        number = Calls[id].anonymous and '' or Calls[id].aNum,
    })

    -- Give up rather than ring for ever: an unanswered call that never clears leaves both
    -- phones stuck reporting they are busy.
    local ring = math.floor(num(S('ringSeconds', Config.Calls.ringSeconds), 30))
    SetTimeout(ring * 1000, function()
        local c = Calls[id]
        if c and c.state == 'ringing' then endCall(id, 'noanswer') end
    end)
    return id, nil
end

local function answerCall(src)
    local id = CallOf[src]
    local c = id and Calls[id]
    if not c or c.state ~= 'ringing' or c.b ~= src then return false end
    c.state, c.at = 'active', os.time()

    TriggerClientEvent('v-phone:client:callActive', c.a, { id = id })
    TriggerClientEvent('v-phone:client:callActive', c.b, { id = id })

    local cap = math.floor(num(S('maxMinutes', Config.Calls.maxMinutes), 30))
    SetTimeout(cap * 60000, function()
        if Calls[id] then endCall(id, 'timeout') end
    end)
    return true
end

-- ══════════════════════════════════════════════════════════════
-- Callbacks
-- ══════════════════════════════════════════════════════════════
-- Either handset counts. Shipping a setting that only accepts one of the two phone items
-- in the catalogue would look like the other one is broken.
local PHONE_ITEMS = { 'phone', 'iphone' }

local function requireItem(src)
    if not V.SettingBool('requireItem', false) then return true end
    local inv = V.Use('v-inventory')
    for _, item in ipairs(PHONE_ITEMS) do
        if num(inv.GetItemCount(src, item), 0) > 0 then return true end
    end
    return false
end

V.Callback('v-phone:open', function(src, resolve)
    if not V.SettingBool('enabled', true) then resolve({ error = 'off' }) return end
    local p = Core.GetPlayer(src)
    if not p then resolve({ error = 'x' }) return end
    if not requireItem(src) then resolve({ error = 'nophone' }) return end

    local number = ensureNumber(src, p)
    local available, installed = appsFrom(src, p)
    resolve({
        ok       = true,
        number   = number,
        apps      = installed,
        available = available,
        prefs    = prefsOf(p),
        contacts = MySQL.query.await(
            'SELECT id, name, number, favourite FROM phone_contacts WHERE citizenid = ? ORDER BY favourite DESC, name',
            { p.citizenid }) or {},
        conversations = conversations(p.citizenid),
        wallpapers = Config.Wallpapers,
        photos     = (function()
            local ph = p.GetMetadata('photos')
            return (type(ph) == 'table') and ph or {}
        end)(),
        camera     = V.SettingBool('camera', false)
                     and (tostring(V.Setting('cameraUpload', '')) ~= '') or false,
        customWallpaper = V.SettingBool('customWallpaper', true),
    })
end)

V.Callback('v-phone:conversation', function(src, resolve, data)
    local p = Core.GetPlayer(src)
    if not p then resolve(false) return end
    local other = cidOfNumber(tostring((data and data.number) or ''))
    if not other then resolve({ error = 'nonumber' }) return end
    resolve({ ok = true, messages = conversation(p.citizenid, other, Config.Messages.pageSize) })
end)

V.Callback('v-phone:send', function(src, resolve, data)
    local p = Core.GetPlayer(src)
    if not p then resolve(false) return end
    local row, err = sendMessage(p.citizenid, tostring((data and data.number) or ''), data and data.body)
    if not row then resolve({ error = err }) return end
    resolve({ ok = true, id = row.id, body = row.body })
end)

V.Callback('v-phone:contactSave', function(src, resolve, data)
    local p = Core.GetPlayer(src)
    if not p then resolve(false) return end
    local name   = tostring((data and data.name) or ''):sub(1, 40)
    local number = tostring((data and data.number) or ''):sub(1, 20)
    if name == '' or number == '' then resolve({ error = 'fields' }) return end
    local fav = (data and data.favourite) and 1 or 0

    local id = tonumber(data and data.id)
    if id then
        -- Scoped to the owner in SQL, not checked afterwards: an UPDATE that trusted the
        -- id alone would let a client rewrite somebody else's contact list.
        MySQL.update.await(
            'UPDATE phone_contacts SET name = ?, number = ?, favourite = ? WHERE id = ? AND citizenid = ?',
            { name, number, fav, id, p.citizenid })
    else
        id = MySQL.insert.await(
            'INSERT INTO phone_contacts (citizenid, name, number, favourite) VALUES (?, ?, ?, ?)',
            { p.citizenid, name, number, fav })
    end
    resolve({ ok = true, id = id })
end)

V.Callback('v-phone:contactDelete', function(src, resolve, data)
    local p = Core.GetPlayer(src)
    if not p then resolve(false) return end
    MySQL.update.await('DELETE FROM phone_contacts WHERE id = ? AND citizenid = ?',
        { tonumber(data and data.id) or 0, p.citizenid })
    resolve({ ok = true })
end)

V.Callback('v-phone:prefs', function(src, resolve, data)
    local p = Core.GetPlayer(src)
    if not p then resolve(false) return end
    local prefs = prefsOf(p)
    if data then
        if data.wallpaper then prefs.wallpaper = tostring(data.wallpaper) end
        if data.ringtone  then prefs.ringtone  = tostring(data.ringtone) end
        if data.dnd ~= nil then prefs.dnd = data.dnd == true end
        if data.wallpaperUrl ~= nil then
            local url = tostring(data.wallpaperUrl):sub(1, 400)
            if url ~= '' and not wallpaperAllowed(url) then resolve({ error = 'badhost' }) return end
            prefs.wallpaperUrl = (url ~= '') and url or nil
        end
        if data.wallFit ~= nil then prefs.wallFit = (data.wallFit == 'contain') and 'contain' or 'cover' end
        if data.size ~= nil then prefs.size = math.max(0.75, math.min(1.15, num(data.size, 1.0))) end
        if data.side ~= nil then prefs.side = (data.side == 'left') and 'left' or 'right' end
        if data.layout ~= nil then
            prefs.layout = (type(data.layout) == 'table') and data.layout or nil
        end
        if data.actionApp ~= nil then
            prefs.actionApp = (data.actionApp ~= '') and tostring(data.actionApp) or nil
        end
        if data.glass ~= nil then
            prefs.glass = math.max(0, math.min(100, math.floor(num(data.glass, Config.DefaultGlass))))
        end
    end
    p.SetMetadata('phone', prefs)
    resolve({ ok = true, prefs = prefs })
end)

V.Callback('v-phone:lookup', function(src, resolve, data)
    -- Who a number belongs to, answered only as a name the caller could have learned
    -- anyway. It never returns a citizen id.
    local cid = cidOfNumber(tostring((data and data.number) or ''))
    if not cid then resolve({ error = 'nonumber' }) return end
    local row = MySQL.single.await('SELECT firstname, lastname FROM characters WHERE citizenid = ?', { cid })
    resolve({ ok = true, name = row and (row.firstname .. ' ' .. row.lastname) or nil })
end)

--- The jobs app is read-only on purpose. `v-cityhall:take` is gated on standing at a
--- desk, and it should stay that way: browsing vacancies from a sofa is fine, signing on
--- from one is not. The list comes from v-cityhall so there is one definition of "open".
V.Callback('v-phone:jobs', function(src, resolve)
    if GetResourceState('v-cityhall') ~= 'started' then resolve({ error = 'off' }) return end
    local p = Core.GetPlayer(src)
    if not p then resolve(false) return end
    resolve({
        ok = true,
        jobs = V.Use('v-cityhall').OpenPositions() or {},
        current = (p.job and p.job.name) or 'unemployed',
    })
end)

--- Per app, per character. An app that wants to remember something needs no table, no
--- migration and no server file: it calls Phone.storage.set and the value is here next
--- session. Values are stored as text; anything structured is the app's own JSON,
--- because guessing at a schema for somebody else's data helps nobody.
V.Callback('v-phone:storage', function(src, resolve, data)
    local p = Core.GetPlayer(src)
    if not p then resolve(false) return end
    local app = tostring((data and data.app) or ''):gsub('[^%w_-]', ''):sub(1, 40)
    if app == '' then resolve({ error = 'forbidden' }) return end
    local op = tostring((data and data.op) or 'get')

    if op == 'all' then
        local out = {}
        for _, r in ipairs(MySQL.query.await(
            'SELECT k, v FROM phone_app_data WHERE citizenid = ? AND app = ?',
            { p.citizenid, app }) or {}) do out[r.k] = r.v end
        resolve({ ok = true, values = out })
        return
    end

    local key = tostring((data and data.key) or ''):sub(1, 60)
    if key == '' then resolve({ error = 'key' }) return end

    if op == 'set' then
        local value = data.value
        if type(value) == 'table' then value = json.encode(value) end
        value = tostring(value == nil and '' or value):sub(1, 4000)
        MySQL.query.await([[INSERT INTO phone_app_data (citizenid, app, k, v) VALUES (?,?,?,?)
            ON DUPLICATE KEY UPDATE v = VALUES(v)]], { p.citizenid, app, key, value })
        resolve({ ok = true })
        return
    end

    resolve({ ok = true, value = MySQL.scalar.await(
        'SELECT v FROM phone_app_data WHERE citizenid = ? AND app = ? AND k = ?',
        { p.citizenid, app, key }) })
end)

--- Everywhere the map already shows. v-world owns every one of these lists, and each is
--- public information: these are places with blips on them, not secrets. The app turns a
--- row into a waypoint, which is the one thing a phone map is actually for.
local PLACE_SOURCES = {
    { key = 'garage',   getter = 'GetGarages',       icon = 'garage' },
    { key = 'shop',     getter = 'GetShopLocations', icon = 'cart' },
    { key = 'station',  getter = 'GetStations',      icon = 'fuel' },
    { key = 'mechanic', getter = 'GetMechShops',     icon = 'wrench' },
    { key = 'cityhall', getter = 'GetCityHalls',     icon = 'jobs' },
    { key = 'dealer',   getter = 'GetDealers',       icon = 'garage' },
}

--- Install or remove an app for THIS character. It cannot make an app appear that the
--- operator has not permitted, and it cannot remove one the phone needs to work: those
--- are the operator's decision and the phone's, not the player's.
--- The camera's gallery. Only ever URLs: the upload target the operator configured
--- returns one, and a data URI would be megabytes of base64 in a metadata column.
V.Callback('v-phone:photo', function(src, resolve, data)
    local p = Core.GetPlayer(src)
    if not p then resolve(false) return end
    if not V.SettingBool('camera', false) then resolve({ error = 'off' }) return end

    local shots = p.GetMetadata('photos')
    if type(shots) ~= 'table' then shots = {} end

    local op = tostring((data and data.op) or 'list')
    if op == 'add' then
        local url = tostring((data and data.url) or ''):sub(1, 400)
        if url == '' then resolve({ error = 'x' }) return end
        table.insert(shots, 1, url)
        while #shots > 30 do table.remove(shots) end     -- a gallery, not an archive
        p.SetMetadata('photos', shots)
    elseif op == 'del' then
        local i = math.floor(num(data and data.index, 0))
        if shots[i] then table.remove(shots, i) end
        p.SetMetadata('photos', shots)
    end
    resolve({ ok = true, photos = shots })
end)

V.Callback('v-phone:install', function(src, resolve, data)
    local p = Core.GetPlayer(src)
    if not p then resolve(false) return end
    local id = tostring((data and data.app) or '')
    local want = data and data.install == true

    local available = appsFor(src, p)
    local found
    for _, a in ipairs(available) do if a.id == id then found = a break end end
    if not found then resolve({ error = 'unavailable' }) return end
    if found.required and not want then resolve({ error = 'required' }) return end

    local prefs = prefsOf(p)
    local out = {}
    for _, rid in ipairs(prefs.removed or {}) do
        if rid ~= id then out[#out + 1] = rid end
    end
    if not want then out[#out + 1] = id end
    prefs.removed = out
    p.SetMetadata('phone', prefs)
    resolve({ ok = true })
end)

V.Callback('v-phone:places', function(src, resolve)
    if GetResourceState('v-world') ~= 'started' then resolve({ error = 'off' }) return end
    local world = V.Use('v-world')
    local out = {}
    for _, src2 in ipairs(PLACE_SOURCES) do
        for _, r in ipairs(world[src2.getter]() or {}) do
            -- A disabled row is one the operator switched off; it should not be on a map
            -- either, or the phone contradicts the world.
            if r.enabled ~= 0 and r.enabled ~= false and r.x then
                out[#out + 1] = {
                    kind = src2.key, icon = src2.icon,
                    label = r.label or r.id or src2.key,
                    x = r.x, y = r.y, z = r.z or 0.0,
                }
            end
        end
    end
    table.sort(out, function(a, b)
        if a.kind ~= b.kind then return a.kind < b.kind end
        return tostring(a.label) < tostring(b.label)
    end)
    resolve({ ok = true, places = out })
end)

V.Callback('v-phone:call', function(src, resolve, data)
    local p = Core.GetPlayer(src)
    if not p then resolve(false) return end
    local id, err = startCall(src, p, tostring((data and data.number) or ''), data and data.anonymous)
    if not id then resolve({ error = err }) return end
    resolve({ ok = true, id = id })
end)

V.Callback('v-phone:answer', function(src, resolve)
    resolve({ ok = answerCall(src) })
end)

V.Callback('v-phone:hangup', function(src, resolve)
    local id = CallOf[src]
    if id then endCall(id, 'hangup') end
    resolve({ ok = true })
end)

-- ══════════════════════════════════════════════════════════════
-- Exports for other modules
-- ══════════════════════════════════════════════════════════════
exports('GetNumber',     function(cid) return numberOfCid(tostring(cid or '')) end)
exports('NumberOf',      function(src)
    local p = Core.GetPlayer(src)
    return p and numberOfCid(p.citizenid) or nil
end)
exports('FindByNumber',  function(number) return cidOfNumber(tostring(number or '')) end)
exports('IsOnline',      function(number) return Online[tostring(number or '')] ~= nil end)
exports('IsOnCall',      function(src) return CallOf[src] ~= nil end)

--- A notification banner on somebody's phone. The one thing another module usually wants
--- from a phone, and the reason it is an export rather than an event: the caller gets a
--- yes/no back instead of shouting into the void.
exports('Notify', function(src, app, title, body)
    if not Core.GetPlayer(src) then return false end
    TriggerClientEvent('v-phone:client:banner', src, {
        app = tostring(app or ''), title = tostring(title or ''), body = tostring(body or ''),
    })
    return true
end)

-- ══════════════════════════════════════════════════════════════
-- Lifecycle
-- ══════════════════════════════════════════════════════════════
AddEventHandler('v-core:server:onPlayerLoaded', function(src, player)
    ensureNumber(src, player)
end)

AddEventHandler('playerDropped', function()
    local src = source
    local id = CallOf[src]
    if id then endCall(id, 'dropped') end
    for n, s in pairs(Online) do if s == src then Online[n] = nil end end
end)

AddEventHandler('v-world:server:changed', function(domain)
    if domain == 'apps' or not domain then loadWorldApps() end
end)

CreateThread(function()
    while GetResourceState('v-core') ~= 'started' do Wait(100) end
    Core = exports['v-core']:GetCore()

    MySQL.query.await([[CREATE TABLE IF NOT EXISTS `phone_contacts` (
        `id`        INT UNSIGNED NOT NULL AUTO_INCREMENT,
        `citizenid` VARCHAR(16)  NOT NULL,
        `name`      VARCHAR(40)  NOT NULL,
        `number`    VARCHAR(20)  NOT NULL,
        `favourite` TINYINT(1)   NOT NULL DEFAULT 0,
        PRIMARY KEY (`id`),
        KEY `citizenid` (`citizenid`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])

    MySQL.query.await([[CREATE TABLE IF NOT EXISTS `phone_messages` (
        `id`       INT UNSIGNED NOT NULL AUTO_INCREMENT,
        `from_cid` VARCHAR(16)  NOT NULL,
        `to_cid`   VARCHAR(16)  NOT NULL,
        `body`     VARCHAR(1000) NOT NULL,
        `seen`     TINYINT(1)   NOT NULL DEFAULT 0,
        `at`       TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (`id`),
        KEY `from_cid` (`from_cid`),
        KEY `to_cid` (`to_cid`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])

    MySQL.query.await([[CREATE TABLE IF NOT EXISTS `phone_app_data` (
        `citizenid` VARCHAR(16) NOT NULL,
        `app`       VARCHAR(40) NOT NULL,
        `k`         VARCHAR(60) NOT NULL,
        `v`         TEXT,
        PRIMARY KEY (`citizenid`, `app`, `k`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])

    -- The number lives on the character, not in a table of its own: it identifies the
    -- character the same way their name does. Added idempotently so an existing database
    -- upgrades without a migration step nobody would run.
    local hasCol = MySQL.scalar.await([[SELECT 1 FROM information_schema.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'characters' AND COLUMN_NAME = 'phone' LIMIT 1]])
    if not hasCol then
        MySQL.query.await('ALTER TABLE `characters` ADD COLUMN `phone` VARCHAR(20) DEFAULT NULL')
        MySQL.query.await('ALTER TABLE `characters` ADD UNIQUE KEY `phone` (`phone`)')
    end

    for _, a in ipairs(Config.Apps) do registerApp(a.id, a, a.owner) end

    -- Seed the operator's rows from the config, exactly like every other content list: the
    -- config holds the defaults, the database holds the edits.
    local tries = 0
    while not exports['v-world']:IsReady() and tries < 150 do Wait(100); tries = tries + 1 end
    if exports['v-world']:IsReady() then
        exports['v-world']:SeedApps(Config.Apps)
    end
    loadWorldApps()

    -- Any app that registered before v-world was ready still needs its editor row.
    for id, a in pairs(Apps) do
        if not WorldApps[id] then
            MySQL.insert.await([[INSERT IGNORE INTO world_apps
                (id, label, slot, job, job_grade, gang, enabled) VALUES (?,?,?,?,?,?,1)]],
                { id, a.label or id, a.slot or 99, a.job or '', a.jobGrade or 0, a.gang or '' })
        end
    end
    loadWorldApps()

    -- Retention, once at boot. A prune on a timer would be a second thing to reason about
    -- for a table that only grows while people are talking.
    local days = math.floor(num(S('retentionDays', Config.Messages.retentionDays), 30))
    if days > 0 then
        local n = MySQL.update.await('DELETE FROM phone_messages WHERE at < DATE_SUB(NOW(), INTERVAL ? DAY)', { days })
        if n and n > 0 then print(('[v-phone] pruned %d message(s) older than %d days'):format(n, days)) end
    end
end)
