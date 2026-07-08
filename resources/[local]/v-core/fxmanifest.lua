fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'v-core'
author 'vyrriox'
description 'v-core — custom roleplay framework core'
version '0.2.0'

shared_scripts {
    'config/config.lua',
    'shared/functions.lua',
}

client_scripts {
    'client/callbacks.lua',
    'client/functions.lua',
    'client/main.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/functions.lua',
    'server/database.lua',
    'server/callbacks.lua',
    'server/permissions.lua',
    'server/logs.lua',
    'server/player.lua',
    'server/main.lua',
}
