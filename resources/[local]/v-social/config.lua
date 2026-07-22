-- v-social | shared config
--
-- The shared social layer. This module exists because Bleeter, Snapmatic and Hush all
-- need the same thing the rest of the phone deliberately avoids: data SHARED between
-- players - handles, posts, likes, matches. One module owns that model; the phone apps
-- are views of it, exactly as the bank app is a view of v-banking.
--
-- The brands are Rockstar's own. Bleeter and Snapmatic ship in the game; inventing a
-- parallel Twitter would break the world every other module is set in.
Config = {}

-- ── Accounts ───────────────────────────────────────────────────
Config.HandleMin = 3
Config.HandleMax = 20

-- ── Posts ──────────────────────────────────────────────────────
Config.Posts = {
    maxLength = 280,        -- a bleet
    feedSize  = 50,         -- newest N per feed
    retentionDays = 60,     -- 0 keeps everything for ever
}

-- ── Hush ───────────────────────────────────────────────────────
Config.Hush = {
    bioMax = 160,
    dailyLikes = 30,        -- a ceiling, so liking everybody is not a strategy
}

-- Image links (avatars, Snapmatic shots, Hush photos) are URLs other clients will fetch,
-- so the hosts are an operator decision - the same rule, and the same default list, as
-- phone wallpapers.
Config.ImageHosts = {
    'i.imgur.com', 'imgur.com',
    'cdn.discordapp.com', 'media.discordapp.net',
    'i.ibb.co', 'raw.githubusercontent.com',
}
