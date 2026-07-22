fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'v-music'
author 'vyrriox'
description 'v-music — boomboxes, jukeboxes and the car stereo, positional and timestamp-synced (v-core module)'
version '0.2.0'

-- Detected by v-core's module registry (admin panel -> Settings). See DEVELOPERS.md.
v_module 'yes'
v_module_label 'Music'
v_module_category 'gameplay'

dependencies {
    'v-core',
    'v-ui',
    'v-inventory',
    'v-world',
}

shared_script '@v-core/lib/v.lua'

shared_scripts {
    '@v-core/locale/shared.lua',
    'locales/en.lua',
    'locales/fr.lua',
    'config.lua',
}

client_script 'client/main.lua'
server_script 'server/main.lua'

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/app.js',
}
