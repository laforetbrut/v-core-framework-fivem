fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'v-housing'
author 'vyrriox'
description 'v-housing — property and tenancy: houses, apartments and motels (v-core module)'
version '0.2.0'

-- Detected by v-core's module registry (admin panel -> Settings). See DEVELOPERS.md.
v_module 'yes'
v_module_label 'Housing'
v_module_category 'world'

dependencies {
    'v-core',
    'v-inventory',
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
