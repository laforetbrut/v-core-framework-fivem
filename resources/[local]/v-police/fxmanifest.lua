fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'v-police'
author 'vyrriox'
description 'v-police — cuffs, escort, search, charges, jail and the MDT (v-core module)'
version '0.1.1'

-- Detected by v-core's module registry (admin panel -> Settings). See DEVELOPERS.md.
v_module 'yes'
v_module_label 'Police'
v_module_category 'people'

dependencies {
    'v-core',
    'v-ui',
    'v-inventory',
    'v-licenses',
    'v-vehicles',
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
