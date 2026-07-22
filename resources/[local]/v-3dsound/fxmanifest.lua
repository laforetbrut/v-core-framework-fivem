fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'v-3dsound'
author 'vyrriox'
description 'v-3dsound — positional sound primitive: play a sound at a place, heard by everyone near it (v-core module)'
version '0.2.0'

-- Detected by v-core's module registry (admin panel -> Settings). See DEVELOPERS.md.
v_module 'yes'
v_module_label '3D sound'
v_module_category 'other'

dependencies { 'v-core' }

shared_script '@v-core/lib/v.lua'

shared_scripts {
    '@v-core/locale/shared.lua',
    'config.lua',
}

client_script 'client/main.lua'
server_script 'server/main.lua'

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/app.js',
    -- Custom sound files go here, e.g.:
    --   'sounds/siren.ogg',
}
