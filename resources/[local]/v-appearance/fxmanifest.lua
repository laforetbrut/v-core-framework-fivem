fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'v-appearance'
author 'vyrriox'
version '0.1.0'
description 'Appearance engine: single writer of ped appearance, stable (collection,index,texture) identity.'

dependencies { 'v-core' }

shared_script '@v-core/locale/shared.lua'
shared_script 'config.lua'

client_scripts {
    'shared/refs.lua',
    'client/engine.lua',
    'client/migrate.lua',
}

server_scripts {
    'server/main.lua',
}

locales {
    'locales/en.lua',
    'locales/fr.lua',
}
