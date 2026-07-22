fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'v-licenses'
author 'vyrriox'
description 'v-licenses — licences and permits: the single source of truth for "may this character do this" (v-core module)'
version '0.1.0'

dependencies {
    'v-core',
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
