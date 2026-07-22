fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'v-phone-notes'
author 'vyrriox'
description 'v-phone-notes — a worked example: a complete phone app in one HTML file and eight lines of Lua'
version '0.2.0'

-- Deliberately NOT a v-core module: it has no settings of its own, and declaring one
-- would put an empty panel in the admin menu. It is an example of the smallest thing
-- that can be a phone app.
dependencies {
    'v-core',
    'v-phone',
}

shared_script '@v-core/lib/v.lua'

server_script 'server/main.lua'

ui_page 'html/index.html'

files {
    'html/index.html',
}
