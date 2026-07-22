fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'v-clothing'
author 'vyrriox'
description 'v-clothing — clothing store with live preview, auto variations, clothing-as-items & equip/unequip'
version '0.2.0'

-- Detected by v-core's module registry (admin panel -> Settings). See DEVELOPERS.md.
v_module 'yes'
v_module_label 'Clothing'
v_module_category 'gameplay'
dependencies {
    'v-core',
    'v-ui',
    'v-inventory',
    'v-appearance',
    'v-world',        -- owns the store locations + the wearable slot definitions
    'oxmysql',
    -- screenshot-basic is NOT listed: it is only needed for the admin thumbnail scan,
    -- which already guards on GetResourceState. A hard dependency would stop the whole
    -- store from loading on a server that doesn't run it.
}

shared_script '@v-core/lib/v.lua'

shared_scripts {
    '@v-core/locale/shared.lua',
    'locales/en.lua',
    'locales/fr.lua',
    'config.lua',
}

client_script 'client/main.lua'

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua',
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/app.js',
}
