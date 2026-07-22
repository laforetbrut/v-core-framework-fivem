fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'v-cityhall'
author 'vyrriox'
description 'v-cityhall — city hall: take an open job, resign, read your contract (v-core module)'
version '0.2.0'

-- Detected by v-core's module registry (admin panel -> Settings). See DEVELOPERS.md.
v_module 'yes'
v_module_label 'Cityhall'
v_module_category 'civic'
dependencies {
    'v-core',
    'v-ui',
    'v-jobs',
    'v-licenses',   -- the licences counter lives in this panel
    'v-world',
}

shared_scripts {
    '@v-core/locale/shared.lua',
    'locales/en.lua',
    'locales/fr.lua',
    -- The licence section of this panel speaks v-licenses' strings. Sharing the files is
    -- the fix rather than copying the keys: a copy drifts, and a drifted key renders as
    -- the raw key ("lic.buy") in front of a player.
    '@v-licenses/locales/en.lua',
    '@v-licenses/locales/fr.lua',
    'config.lua',
}

client_script 'client/main.lua'

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua',
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/app.js',
}
