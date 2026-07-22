fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'v-anticheat'
author 'vyrriox'
description 'v-anticheat — server-side sanity checks on movement, health, explosions, entities, money and damage (v-core module)'
version '0.2.0'

-- Detected by v-core's module registry (admin panel -> Settings). See DEVELOPERS.md.
v_module 'yes'
v_module_label 'Anticheat'
v_module_category 'other'

dependencies { 'v-core' }

shared_script '@v-core/lib/v.lua'

shared_scripts {
    '@v-core/locale/shared.lua',
    'locales/en.lua',
    'locales/fr.lua',
    'config.lua',
}

server_script 'server/main.lua'
