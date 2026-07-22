fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'v-appearance'
author 'vyrriox'
version '0.1.0'

-- Detected by v-core's module registry (admin panel -> Settings). See DEVELOPERS.md.
v_module 'yes'
v_module_label 'Appearance'
v_module_category 'gameplay'
description 'Appearance engine: single writer of ped appearance, stable identity, barber/surgery/tattoo editor.'

dependencies { 'v-core' }

shared_script '@v-core/lib/v.lua'

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
