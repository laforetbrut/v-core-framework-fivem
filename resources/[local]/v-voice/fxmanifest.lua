fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'v-voice'
author 'vyrriox'
description 'v-voice — proximity voice, radio channels and phone audio (v-core module)'
version '0.1.1'

-- Detected by v-core's module registry (admin panel -> Settings). See DEVELOPERS.md.
v_module 'yes'
v_module_label 'Voice'
v_module_category 'gameplay'

dependencies {
    'v-core',
    'v-world',
}

shared_script '@v-core/lib/v.lua'

shared_scripts {
    '@v-core/locale/shared.lua',
    'locales/en.lua',
    'locales/fr.lua',
    'config.lua',
}

client_script 'client/main.lua'
server_script 'server/main.lua'
