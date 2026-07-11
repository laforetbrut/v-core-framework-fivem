fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'v-jobs'
author 'vyrriox'
description 'v-jobs — jobs, grades, duty & salaries; the source of truth for job-gated shops/stashes/benches (v-core module)'
version '0.1.0'

dependencies {
    'v-core',
}

shared_scripts {
    '@v-core/locale/shared.lua',
    'locales/en.lua',
    'locales/fr.lua',
    'config.lua',
}

server_script 'server/main.lua'
