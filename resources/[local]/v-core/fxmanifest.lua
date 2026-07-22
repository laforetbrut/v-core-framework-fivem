fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'v-core'
author 'vyrriox'
description 'v-core — custom roleplay framework core'
version '0.1.1'

-- v-core is the registry itself, but it lists too so an operator sees it running.
v_module 'yes'
v_module_label 'Core'
v_module_category 'other'
-- The shared helper other resources load with `shared_script '@v-core/lib/v.lua'`.
files { 'lib/v.lua' }

shared_scripts {
    'config/config.lua',
    'locale/shared.lua',
    'locales/en.lua',
    'locales/fr.lua',
    'shared/functions.lua',
}

client_scripts {
    'client/callbacks.lua',
    'client/functions.lua',
    'client/focus.lua',
    'client/world.lua',   -- world policy: NPC police, dispatch, ambient events
    'client/main.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/functions.lua',
    'server/database.lua',
    'server/callbacks.lua',
    'server/permissions.lua',
    'server/logs.lua',
    'server/modules.lua',   -- module registry + live settings (self-describing to v-admin)
    'server/player.lua',
    'server/main.lua',
}
