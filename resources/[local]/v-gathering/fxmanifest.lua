fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'v-gathering'
author 'vyrriox'
description 'v-gathering — resource nodes (mining / salvage / textile) that yield raw crafting materials (v-core module)'
version '0.2.0'

-- Detected by v-core's module registry (admin panel -> Settings). See DEVELOPERS.md.
v_module 'yes'
v_module_label 'Gathering'
v_module_category 'economy'
dependencies {
    'v-core',
    'v-inventory',
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
