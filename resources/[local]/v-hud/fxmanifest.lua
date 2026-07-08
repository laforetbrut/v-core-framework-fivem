fx_version 'cerulean'
game 'gta5'

name 'v-hud'
author 'vyrriox'
description 'v-hud — money HUD for Projet R (v-core module)'
version '0.1.0'

dependencies {
    'v-core',
    'v-status',
}

ui_page 'html/index.html'

shared_scripts {
    '@v-core/locale/shared.lua',
    'locales/en.lua',
    'locales/fr.lua',
}

client_script 'client.lua'

files {
    'html/index.html',
    'html/style.css',
    'html/app.js',
}
