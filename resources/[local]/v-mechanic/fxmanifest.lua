fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'v-mechanic'
author 'vyrriox'
description 'v-mechanic — per-part vehicle wear, odometer, diagnostics and repairs (v-core module)'
version '0.1.0'

-- Detected by v-core's module registry (admin panel -> Settings). See INTEGRATION.md.
v_module 'yes'
v_module_label 'Mechanic'
v_module_category 'vehicles'
dependencies {
    'v-core',
    'v-ui',
    'v-vehicles',
    'v-inventory',
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

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/app.js',
}
