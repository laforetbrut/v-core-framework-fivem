fx_version 'cerulean'
game 'gta5'

name 'v-notify'
author 'vyrriox'
description 'v-notify — themed NUI notifications / toasts (v-core module)'
version '0.1.0'

-- Detected by v-core's module registry (admin panel -> Settings). See INTEGRATION.md.
v_module 'yes'
v_module_label 'Notify'
v_module_category 'gameplay'
dependency 'v-ui'

ui_page 'html/index.html'

client_script 'client.lua'

files {
    'html/index.html',
    'html/style.css',
    'html/app.js',
}

-- registers this module's settings with v-core (see INTEGRATION.md)
server_script 'server/settings.lua'
