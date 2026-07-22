fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'v-factions'
author 'vyrriox'
description 'v-factions — shared organisation layer: membership, ranks and treasuries (v-core module)'
version '0.1.1'

-- Detected by v-core's module registry (admin panel -> Settings). See DEVELOPERS.md.
v_module 'yes'
v_module_label 'Factions'
v_module_category 'people'

dependencies {
    'v-core',
    'v-jobs',
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

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua',
}
