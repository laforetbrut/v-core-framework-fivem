fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'v-fuel'
author 'vyrriox'
description 'v-fuel — fuel types, consumption and gas / charging stations (v-core module)'
version '0.1.0'

dependencies {
    'v-core',
    'v-ui',
    'v-vehicles',
    'v-inventory',   -- the jerry can is an item like any other
    'v-world',
    'oxmysql',
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
    'server/main.lua',
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/app.js',
}
