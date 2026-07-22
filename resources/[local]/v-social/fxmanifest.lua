fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'v-social'
author 'vyrriox'
description 'v-social — the shared social layer: accounts, posts, likes and dating, that the phone apps are views of (v-core module)'
version '0.2.0'

-- Detected by v-core's module registry (admin panel -> Settings). See DEVELOPERS.md.
v_module 'yes'
v_module_label 'Social'
v_module_category 'gameplay'

dependencies {
    'v-core',
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
