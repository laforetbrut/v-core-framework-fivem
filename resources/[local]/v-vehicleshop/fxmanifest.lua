fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'v-vehicleshop'
author 'vyrriox'
description 'v-vehicleshop — dealerships: browse, test drive and buy a vehicle (v-core module)'
version '0.2.0'

-- Detected by v-core's module registry (admin panel -> Settings). See DEVELOPERS.md.
v_module 'yes'
v_module_label 'Vehicleshop'
v_module_category 'vehicles'
dependencies {
    'v-core',
    'v-ui',
    'v-vehicles',
    'v-licenses',
    'v-world',
    'oxmysql',
}

shared_script '@v-core/lib/v.lua'

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
