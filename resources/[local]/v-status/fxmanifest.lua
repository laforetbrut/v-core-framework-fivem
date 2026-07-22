fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'v-status'
author 'vyrriox'
description 'v-status — hunger, thirst, stress, injuries & illness (v-core module)'
version '0.2.0'

-- Detected by v-core's module registry (admin panel -> Settings). See DEVELOPERS.md.
v_module 'yes'
v_module_label 'Status'
v_module_category 'gameplay'
dependency 'v-core'

shared_script '@v-core/lib/v.lua'

shared_script 'config.lua'
client_script 'client/main.lua'
server_script 'server/main.lua'
