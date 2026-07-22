fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'v-ui'
author 'vyrriox'
description 'v-ui — EMBER design system: the single source of truth for every NUI in the framework'
version '0.1.0'

-- Detected by v-core's module registry (admin panel -> Settings). See DEVELOPERS.md.
v_module 'yes'
v_module_label 'Interface'
v_module_category 'other'

shared_script '@v-core/lib/v.lua'

shared_script 'config.lua'

client_script 'client/main.lua'

server_scripts {
    'server/main.lua',
}

files {
    'theme.css',        -- primitives (static)
    'theme-vars.css',   -- palette (generated from config + admin settings)
    'theme.js',         -- re-links theme-vars.css when the theme changes
}
