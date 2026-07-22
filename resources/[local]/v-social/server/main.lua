-- v-social | server
--
-- The one place player-shared social data lives. Three rules shape everything here:
--
--  1. **The author is always the server's idea of who called**, never a field in the
--     payload. A client that could name the author of a post could bleet as the mayor.
--
--  2. **Handles address people; citizen ids never leave the server.** A handle is the
--     public name an account chose. The citizen id is a database key, and every query
--     that answers a client resolves ids to handles before it resolves at all.
--
--  3. **A Hush match is the only place identity crosses over**, and it is the point:
--     both sides liked, so both sides get the other's NAME and NUMBER - through v-phone,
--     which owns numbers - and nothing else.

V.Provide('social')

local Core

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
    label = 'Social', category = 'gameplay',
    settings = {
        { key = 'enabled', label = 'Social apps enabled', type = 'bool', default = true,
          hint = 'Off hides Bleeter, Snapmatic and Hush from every phone. Accounts and posts are kept.' },

        { key = 'maxLength', label = 'Bleet length limit', type = 'number',
          default = Config.Posts.maxLength, min = 40, max = 1000, step = 10 },

        { key = 'retentionDays', label = 'Keep posts for (days)', type = 'number',
          default = Config.Posts.retentionDays, min = 0, max = 365, step = 1,
          hint = 'Pruned once at boot. 0 keeps everything for ever, which is a feed nobody trims.' },

        { key = 'hush', label = 'Hush (dating) enabled', type = 'bool', default = true },

        { key = 'dailyLikes', label = 'Hush likes per day', type = 'number',
          default = Config.Hush.dailyLikes, min = 1, max = 500, step = 1,
          hint = 'A ceiling, so liking absolutely everybody is not a strategy.' },

        { key = 'imageHosts', label = 'Image hosts', type = 'string',
          default = table.concat(Config.ImageHosts, ', '),
          hint = 'Comma separated. Avatars and photos are URLs other clients will fetch, so this is an operator decision - the same rule as phone wallpapers.' },
    },
})

local function S(key, fallback) return V.Setting(key, fallback) end

--- Same shape as the phone's wallpaper gate, for the same reason. Rejected rather than
--- rewritten: silently fixing somebody's link is worse than telling them it is refused.
local function imageAllowed(url)
    url = tostring(url or '')
    if url == '' then return true end
    local host = url:match('^https?://([^/]+)')
    if not host then return false end
    host = host:lower():gsub(':%d+$', '')
    local hosts = S('imageHosts', Config.ImageHosts)
    if type(hosts) == 'string' then
        local out = {}
        for h in hosts:gmatch('[^,%s]+') do out[#out + 1] = h end
        hosts = out
    end
    for _, allowed in ipairs(hosts or Config.ImageHosts) do
        if host == allowed or host:sub(-(#allowed + 1)) == '.' .. allowed then return true end
    end
    return false
end

-- ══════════════════════════════════════════════════════════════
-- Accounts
-- ══════════════════════════════════════════════════════════════
local function accountOf(cid)
    return MySQL.single.await(
        'SELECT citizenid, handle, avatar, bio FROM social_accounts WHERE citizenid = ?', { cid })
end

local function publicAccount(a)
    -- The citizen id stops here.
    return a and { handle = a.handle, avatar = a.avatar, bio = a.bio } or nil
end

V.Callback('v-social:me', function(src, resolve)
    if not V.SettingBool('enabled', true) then resolve({ error = 'off' }) return end
    local p = Core.GetPlayer(src)
    if not p then resolve(false) return end
    resolve({ ok = true, account = publicAccount(accountOf(p.citizenid)) })
end)

V.Callback('v-social:setup', function(src, resolve, data)
    local p = Core.GetPlayer(src)
    if not p then resolve(false) return end

    local handle = tostring((data and data.handle) or ''):gsub('[^%w_]', ''):sub(1, Config.HandleMax)
    if #handle < Config.HandleMin then resolve({ error = 'handle' }) return end
    local avatar = tostring((data and data.avatar) or ''):sub(1, 300)
    if avatar ~= '' and not imageAllowed(avatar) then resolve({ error = 'badhost' }) return end
    local bio = tostring((data and data.bio) or ''):sub(1, 160)

    -- One handle per server, checked against everyone else but not against yourself, so
    -- editing your own bio does not collide with your own name.
    local taken = MySQL.scalar.await(
        'SELECT 1 FROM social_accounts WHERE handle = ? AND citizenid <> ? LIMIT 1',
        { handle, p.citizenid })
    if taken then resolve({ error = 'taken' }) return end

    MySQL.query.await([[INSERT INTO social_accounts (citizenid, handle, avatar, bio)
        VALUES (?,?,?,?)
        ON DUPLICATE KEY UPDATE handle=VALUES(handle), avatar=VALUES(avatar), bio=VALUES(bio)]],
        { p.citizenid, handle, avatar, bio })
    resolve({ ok = true, account = { handle = handle, avatar = avatar, bio = bio } })
end)

-- ══════════════════════════════════════════════════════════════
-- The feed
-- ══════════════════════════════════════════════════════════════
-- One table, two kinds. Bleeter shows 'text', Snapmatic shows 'photo': the same feed with
-- different content types and different chrome, which is all those two apps ever were.
V.Callback('v-social:feed', function(src, resolve, data)
    if not V.SettingBool('enabled', true) then resolve({ error = 'off' }) return end
    local p = Core.GetPlayer(src)
    if not p then resolve(false) return end
    local kind = (data and data.kind == 'photo') and 'photo' or 'text'

    local rows = MySQL.query.await([[
        SELECT s.id, s.kind, s.body, s.image, s.at,
               a.handle, a.avatar,
               (SELECT COUNT(*) FROM social_likes l WHERE l.post_id = s.id) AS likes,
               EXISTS(SELECT 1 FROM social_likes l2 WHERE l2.post_id = s.id AND l2.citizenid = ?) AS liked,
               (s.citizenid = ?) AS mine
        FROM social_posts s
        JOIN social_accounts a ON a.citizenid = s.citizenid
        WHERE s.kind = ?
        ORDER BY s.id DESC LIMIT ?
    ]], { p.citizenid, p.citizenid, kind, Config.Posts.feedSize }) or {}

    for _, r in ipairs(rows) do
        r.likes = num(r.likes, 0)
        r.liked = num(r.liked, 0) == 1
        r.mine = num(r.mine, 0) == 1
    end
    resolve({ ok = true, posts = rows })
end)

V.Callback('v-social:post', function(src, resolve, data)
    local p = Core.GetPlayer(src)
    if not p then resolve(false) return end
    if not accountOf(p.citizenid) then resolve({ error = 'noaccount' }) return end

    local kind = (data and data.kind == 'photo') and 'photo' or 'text'
    local body = tostring((data and data.body) or '')
        :sub(1, math.floor(num(S('maxLength', Config.Posts.maxLength), 280)))
    local image = tostring((data and data.image) or ''):sub(1, 300)

    if kind == 'photo' then
        -- A photo post is the photo; a caption is optional. And the URL faces every
        -- client that opens the feed, so it goes through the host gate.
        if image == '' then resolve({ error = 'noimage' }) return end
        if not imageAllowed(image) then resolve({ error = 'badhost' }) return end
    else
        if body:gsub('%s', '') == '' then resolve({ error = 'empty' }) return end
        image = ''
    end

    local id = MySQL.insert.await(
        'INSERT INTO social_posts (citizenid, kind, body, image) VALUES (?,?,?,?)',
        { p.citizenid, kind, body, image })
    Core.Log('social', ('%s posted %s #%d'):format(p.citizenid, kind, id), nil, p.citizenid)
    resolve({ ok = true, id = id })
end)

V.Callback('v-social:like', function(src, resolve, data)
    local p = Core.GetPlayer(src)
    if not p then resolve(false) return end
    local id = math.floor(num(data and data.id, 0))
    if id <= 0 then resolve(false) return end

    -- A like is a toggle. INSERT IGNORE + DELETE keyed on the pair means double-clicking
    -- can never count twice, whatever order the packets land in.
    local liked
    local exists = MySQL.scalar.await(
        'SELECT 1 FROM social_likes WHERE post_id = ? AND citizenid = ?', { id, p.citizenid })
    if exists then
        MySQL.query.await('DELETE FROM social_likes WHERE post_id = ? AND citizenid = ?', { id, p.citizenid })
        liked = false
    else
        MySQL.insert.await('INSERT IGNORE INTO social_likes (post_id, citizenid) VALUES (?,?)', { id, p.citizenid })
        liked = true
    end
    local count = num(MySQL.scalar.await(
        'SELECT COUNT(*) FROM social_likes WHERE post_id = ?', { id }), 0)
    resolve({ ok = true, liked = liked, likes = count })
end)

-- ══════════════════════════════════════════════════════════════
-- Hush
-- ══════════════════════════════════════════════════════════════
local function hushOn() return V.SettingBool('enabled', true) and V.SettingBool('hush', true) end

V.Callback('v-social:hushMe', function(src, resolve)
    if not hushOn() then resolve({ error = 'off' }) return end
    local p = Core.GetPlayer(src)
    if not p then resolve(false) return end
    local row = MySQL.single.await(
        'SELECT bio, photo, active FROM hush_profiles WHERE citizenid = ?', { p.citizenid })
    resolve({ ok = true, profile = row and { bio = row.bio, photo = row.photo, active = num(row.active, 0) == 1 } or nil })
end)

V.Callback('v-social:hushSetup', function(src, resolve, data)
    if not hushOn() then resolve({ error = 'off' }) return end
    local p = Core.GetPlayer(src)
    if not p then resolve(false) return end
    local bio = tostring((data and data.bio) or ''):sub(1, Config.Hush.bioMax)
    local photo = tostring((data and data.photo) or ''):sub(1, 300)
    if photo ~= '' and not imageAllowed(photo) then resolve({ error = 'badhost' }) return end
    local active = (data and data.active == false) and 0 or 1

    MySQL.query.await([[INSERT INTO hush_profiles (citizenid, bio, photo, active)
        VALUES (?,?,?,?)
        ON DUPLICATE KEY UPDATE bio=VALUES(bio), photo=VALUES(photo), active=VALUES(active)]],
        { p.citizenid, bio, photo, active })
    resolve({ ok = true })
end)

--- The next profile this player has not judged yet. The citizen id travels as an opaque
--- `ref` the client hands straight back - it is never displayed, and the visible fields
--- are the first name and an age derived from the date of birth, which is how a dating
--- profile introduces somebody.
V.Callback('v-social:hushNext', function(src, resolve)
    if not hushOn() then resolve({ error = 'off' }) return end
    local p = Core.GetPlayer(src)
    if not p then resolve(false) return end

    local row = MySQL.single.await([[
        SELECT h.citizenid, h.bio, h.photo, c.firstname, c.dob
        FROM hush_profiles h
        JOIN characters c ON c.citizenid = h.citizenid
        WHERE h.active = 1 AND h.citizenid <> ?
          AND NOT EXISTS (SELECT 1 FROM hush_likes l
                          WHERE l.from_cid = ? AND l.to_cid = h.citizenid)
        ORDER BY RAND() LIMIT 1
    ]], { p.citizenid, p.citizenid })
    if not row then resolve({ ok = true, profile = nil }) return end

    local year = tostring(row.dob or ''):match('^(%d%d%d%d)')
    local age = year and math.max(18, 2026 - tonumber(year)) or nil
    resolve({ ok = true, profile = {
        ref = row.citizenid, name = row.firstname, age = age,
        bio = row.bio, photo = row.photo,
    } })
end)

V.Callback('v-social:hushChoice', function(src, resolve, data)
    if not hushOn() then resolve({ error = 'off' }) return end
    local p = Core.GetPlayer(src)
    if not p then resolve(false) return end
    local target = tostring((data and data.ref) or '')
    if target == '' or target == p.citizenid then resolve(false) return end

    local liked = data and data.like == true
    -- A pass is recorded too, or the same face comes back every time the app opens.
    MySQL.insert.await(
        'INSERT IGNORE INTO hush_likes (from_cid, to_cid, liked) VALUES (?,?,?)',
        { p.citizenid, target, liked and 1 or 0 })

    if not liked then resolve({ ok = true, match = false }) return end

    -- The daily ceiling counts LIKES, not passes: saying no is free.
    local today = num(MySQL.scalar.await([[SELECT COUNT(*) FROM hush_likes
        WHERE from_cid = ? AND liked = 1 AND at > DATE_SUB(NOW(), INTERVAL 1 DAY)]],
        { p.citizenid }), 0)
    if today > math.floor(num(S('dailyLikes', Config.Hush.dailyLikes), 30)) then
        MySQL.query.await('DELETE FROM hush_likes WHERE from_cid = ? AND to_cid = ?', { p.citizenid, target })
        resolve({ error = 'limit' }) return
    end

    local mutual = MySQL.scalar.await(
        'SELECT 1 FROM hush_likes WHERE from_cid = ? AND to_cid = ? AND liked = 1',
        { target, p.citizenid })
    if not mutual then resolve({ ok = true, match = false }) return end

    -- The match: the one moment identity crosses, because both sides asked for it. Names
    -- and numbers travel through v-phone, which owns numbers; each side gets a message
    -- from the other, so the conversation already exists when they open it.
    local phone = V.Use('v-phone')
    local myNumber = phone.GetNumber(p.citizenid)
    local theirNumber = phone.GetNumber(target)
    local them = MySQL.single.await('SELECT firstname FROM characters WHERE citizenid = ?', { target })

    if myNumber and theirNumber then
        phone.SendMessage(p.citizenid, theirNumber, L(src, 'soc.match_line'))
        phone.SendMessage(target, myNumber, L(src, 'soc.match_line'))
    end
    Core.Log('social', ('hush match %s <-> %s'):format(p.citizenid, target), nil, p.citizenid)
    resolve({ ok = true, match = true, name = them and them.firstname or '?', number = theirNumber })
end)

-- ══════════════════════════════════════════════════════════════
-- Exports for other modules
-- ══════════════════════════════════════════════════════════════
exports('GetHandle', function(cid)
    local a = accountOf(tostring(cid or ''))
    return a and a.handle or nil
end)

--- Post as the system/an event, for modules that want to put something on Bleeter (a
--- news module, a race result). `handle` must be an account that exists.
exports('PostAs', function(cid, kind, body, image)
    cid = tostring(cid or '')
    if not accountOf(cid) then return false end
    return MySQL.insert.await(
        'INSERT INTO social_posts (citizenid, kind, body, image) VALUES (?,?,?,?)',
        { cid, kind == 'photo' and 'photo' or 'text', tostring(body or ''):sub(1, 280),
          tostring(image or ''):sub(1, 300) }) ~= nil
end)

-- ══════════════════════════════════════════════════════════════
-- Lifecycle
-- ══════════════════════════════════════════════════════════════
CreateThread(function()
    while GetResourceState('v-core') ~= 'started' do Wait(100) end
    Core = exports['v-core']:GetCore()

    MySQL.query.await([[CREATE TABLE IF NOT EXISTS `social_accounts` (
        `citizenid` VARCHAR(16) NOT NULL,
        `handle`    VARCHAR(20) NOT NULL,
        `avatar`    VARCHAR(300) NOT NULL DEFAULT '',
        `bio`       VARCHAR(160) NOT NULL DEFAULT '',
        PRIMARY KEY (`citizenid`),
        UNIQUE KEY `handle` (`handle`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])

    MySQL.query.await([[CREATE TABLE IF NOT EXISTS `social_posts` (
        `id`        INT UNSIGNED NOT NULL AUTO_INCREMENT,
        `citizenid` VARCHAR(16) NOT NULL,
        `kind`      VARCHAR(8)  NOT NULL DEFAULT 'text',
        `body`      VARCHAR(1000) NOT NULL DEFAULT '',
        `image`     VARCHAR(300) NOT NULL DEFAULT '',
        `at`        TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (`id`), KEY `kind_idx` (`kind`, `id`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])

    MySQL.query.await([[CREATE TABLE IF NOT EXISTS `social_likes` (
        `post_id`   INT UNSIGNED NOT NULL,
        `citizenid` VARCHAR(16) NOT NULL,
        PRIMARY KEY (`post_id`, `citizenid`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])

    MySQL.query.await([[CREATE TABLE IF NOT EXISTS `hush_profiles` (
        `citizenid` VARCHAR(16) NOT NULL,
        `bio`       VARCHAR(160) NOT NULL DEFAULT '',
        `photo`     VARCHAR(300) NOT NULL DEFAULT '',
        `active`    TINYINT(1) NOT NULL DEFAULT 1,
        PRIMARY KEY (`citizenid`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])

    MySQL.query.await([[CREATE TABLE IF NOT EXISTS `hush_likes` (
        `from_cid` VARCHAR(16) NOT NULL,
        `to_cid`   VARCHAR(16) NOT NULL,
        `liked`    TINYINT(1) NOT NULL DEFAULT 0,
        `at`       TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (`from_cid`, `to_cid`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])

    -- Retention, once at boot, same policy as phone messages.
    local days = math.floor(num(S('retentionDays', Config.Posts.retentionDays), 60))
    if days > 0 then
        local n = MySQL.update.await(
            'DELETE FROM social_posts WHERE at < DATE_SUB(NOW(), INTERVAL ? DAY)', { days })
        if n and n > 0 then print(('[v-social] pruned %d post(s) older than %d days'):format(n, days)) end
    end
end)
