fx_version 'bodacious'
game 'gta5'
lua54 'yes'
author 'Kakarot'
description 'Allows players to access a phone to interact with various apps and features'
version '1.5.0'

shared_scripts {
    'config.lua',
    '@qb-apartments/config.lua'
}

client_script 'client.lua'

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server.lua'
}

ui_page 'html/index.html'

files {
    'html/*.html',
    'html/js/*.js',
    'html/img/*.png',
    'html/css/*.css',
    'html/img/backgrounds/*.png',
    'html/img/apps/*.png',
}
