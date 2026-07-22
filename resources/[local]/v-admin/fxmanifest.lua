fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'v-admin'
author 'vyrriox'
description 'v-admin — in-game admin panel: players, resources, world, economy, logs'
version '0.1.1'

-- Detected by v-core's module registry (admin panel -> Settings). See DEVELOPERS.md.
v_module 'yes'
v_module_label 'Admin'
v_module_category 'other'
dependencies {
    'v-core',
    'v-ui',
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
