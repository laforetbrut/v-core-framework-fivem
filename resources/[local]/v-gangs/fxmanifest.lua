fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'v-gangs'
author 'vyrriox'
description 'v-gangs — gang territory: capture, influence and turf ownership (v-core module)'
version '0.2.0'

-- Detected by v-core's module registry (admin panel -> Settings). See DEVELOPERS.md.
v_module 'yes'
v_module_label 'Gangs'
v_module_category 'people'

dependencies {
    'v-core',
    'v-factions',
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
