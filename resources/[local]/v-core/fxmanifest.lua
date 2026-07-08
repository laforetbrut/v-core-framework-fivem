fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'v-core'
author 'vyrriox'
description 'v-core — custom roleplay framework core'
version '0.1.0'

shared_scripts {
    'config/config.lua',
    'shared/functions.lua',
}

client_scripts {
    'client/functions.lua',
    'client/main.lua',
}

server_scripts {
    'server/functions.lua',
    'server/player.lua',
    'server/main.lua',
}
