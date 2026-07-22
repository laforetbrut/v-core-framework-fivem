fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'v-target'
author 'vyrriox'
description 'v-target — universal interaction eye: entity/zone options filtered by permission, job & item (v-core module)'
version '0.1.0'

-- Detected by v-core's module registry (admin panel -> Settings). See INTEGRATION.md.
v_module 'yes'
v_module_label 'Target'
v_module_category 'gameplay'
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

client_scripts {
    'client/main.lua',
    'client/interactions.lua',
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/app.js',
}
