fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'v-vehicles'
author 'vyrriox'
description 'v-vehicles — owned-vehicle persistence, server-minted plates and the key system (v-core module)'
version '0.1.0'

dependencies {
    'v-core',
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
