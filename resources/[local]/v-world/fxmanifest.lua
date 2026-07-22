fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'v-world'
author 'vyrriox'
description 'v-world — admin-editable world content: blips, shop locations and jobs (DB-backed, live-synced)'
version '0.1.0'

-- Detected by v-core's module registry (admin panel -> Settings). See INTEGRATION.md.
v_module 'yes'
v_module_label 'World'
v_module_category 'other'
dependencies {
    'v-core',
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
