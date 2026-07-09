fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'v-clothing'
author 'vyrriox'
description 'v-clothing — clothing store with live preview, auto variations, clothing-as-items & equip/unequip'
version '0.1.0'

dependencies {
    'v-core',
    'v-ui',
    'v-inventory',
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
