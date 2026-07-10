fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'v-inventory'
author 'vyrriox'
description 'v-inventory — grid inventory: weight, use/drop/give, vehicle trunk & stashes (v-core module)'
version '0.1.0'

dependencies {
    'v-core',
    'v-ui',
}

shared_scripts {
    '@v-core/locale/shared.lua',
    'locales/en.lua',
    'locales/fr.lua',
    'config.lua',
}

client_script 'client/main.lua'

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'data/items.lua',
    'server/main.lua',
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/app.js',
    'html/images/**/*.png',
}
