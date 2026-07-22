fx_version 'cerulean'
game 'gta5'

name 'v-notify'
author 'vyrriox'
description 'v-notify — themed NUI notifications / toasts (v-core module)'
version '0.1.1'

-- Detected by v-core's module registry (admin panel -> Settings). See DEVELOPERS.md.
v_module 'yes'
v_module_label 'Notify'
v_module_category 'gameplay'
dependency 'v-ui'

ui_page 'html/index.html'

shared_script '@v-core/lib/v.lua'

client_script 'client.lua'

files {
    'html/index.html',
    'html/style.css',
    'html/app.js',
}

-- registers this module's settings with v-core (see DEVELOPERS.md)
server_script 'server/settings.lua'
