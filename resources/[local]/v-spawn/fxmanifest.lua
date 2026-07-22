fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'v-spawn'
author 'vyrriox'
description 'v-spawn — language selection, character creation & appearance editor (v-core module)'
version '0.1.0'

-- Detected by v-core's module registry (admin panel -> Settings). See INTEGRATION.md.
v_module 'yes'
v_module_label 'Spawn'
v_module_category 'gameplay'
dependencies { 'v-core', 'v-appearance' }

shared_scripts {
    '@v-core/locale/shared.lua',
    'locales/en.lua',
    'locales/fr.lua',
    'config.lua',
}

client_scripts {
    'client/ped.lua',
    'client/camera.lua',
    'client/main.lua',
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/app.js',
}
