fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'v-loadscreen'
author 'doc, vyrriox'
description 'v-loadscreen — animated loading screen: backgrounds, music player, tips and keybinds (v-core module)'
version '0.2.0'

-- Detected by v-core's module registry (admin panel -> Settings). See DEVELOPERS.md.
v_module 'yes'
v_module_label 'Loadscreen'
v_module_category 'other'

-- The screen is HTML. It holds cursor focus so the music and background controls are
-- clickable, and closes itself (manual shutdown) once the player is actually in the
-- world, with a failsafe so a stalled session can never strand anybody on it.
loadscreen 'index.html'
loadscreen_cursor 'yes'
loadscreen_manual_shutdown 'yes'

client_script 'client.lua'
server_script 'server.lua'

files {
    'index.html',
    'config.js',
    'web/style.css',
    'web/app.js',
    'web/fonts/*.woff2',
    'assets/logo.webp',
    'assets/backgrounds/*.webm',
    'assets/backgrounds/*.webp',
    'assets/backgrounds/*.jpg',
    'assets/music/*.mp3',
    'assets/music/*.ogg',
}
