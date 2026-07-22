fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'v-licenses'
author 'vyrriox'
description 'v-licenses — licences and permits: the single source of truth for "may this character do this" (v-core module)'
version '0.2.0'

-- Detected by v-core's module registry (admin panel -> Settings). See DEVELOPERS.md.
v_module 'yes'
v_module_label 'Licenses'
v_module_category 'law'
dependencies {
    'v-core',
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
