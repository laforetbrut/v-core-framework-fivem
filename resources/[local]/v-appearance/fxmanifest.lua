fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'v-appearance'
author 'vyrriox'
version '0.2.0'
description 'Appearance engine: single writer of ped appearance, stable identity, barber/surgery/tattoo editor.'

dependencies { 'v-core' }

shared_scripts {
    '@v-core/locale/shared.lua',
    'locales/en.lua',
    'locales/fr.lua',
    'config.lua',
}

client_scripts {
    'data/tattoos.lua',
    'shared/refs.lua',
    'client/engine.lua',
    'client/migrate.lua',
    'client/camera.lua',
    'client/editor.lua',
    'client/stations.lua',
}

server_scripts {
    'server/main.lua',
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/app.js',
}
