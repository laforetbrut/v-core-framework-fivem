fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'v-crafting'
author 'vyrriox'
description 'v-crafting — workbench crafting: recipes consume inventory items to produce new ones (v-core module)'
version '0.1.0'

-- Detected by v-core's module registry (admin panel -> Settings). See INTEGRATION.md.
v_module 'yes'
v_module_label 'Crafting'
v_module_category 'economy'
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
