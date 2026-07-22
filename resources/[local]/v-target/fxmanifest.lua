fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'v-target'
author 'vyrriox'
description 'v-target — universal interaction eye: entity/zone options filtered by permission, job & item (v-core module)'
version '0.1.0'

-- Detected by v-core's module registry (admin panel -> Settings). See DEVELOPERS.md.
v_module 'yes'
v_module_label 'Target'
v_module_category 'gameplay'
dependencies {
    'v-core',
    'v-ui',
}

shared_script '@v-core/lib/v.lua'

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

-- registers this module's settings with v-core (see DEVELOPERS.md)
server_script 'server/settings.lua'
