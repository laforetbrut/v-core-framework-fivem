fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'v-phone'
author 'vyrriox'
description 'v-phone — iFruit: the primary interaction surface, a shell over the modules that own the data (v-core module)'
version '0.2.0'

-- Detected by v-core's module registry (admin panel -> Settings). See DEVELOPERS.md.
v_module 'yes'
v_module_label 'Phone'
v_module_category 'gameplay'

dependencies {
    'v-core',
    'v-ui',
    'v-world',
    'oxmysql',
}

shared_script '@v-core/lib/v.lua'

shared_scripts {
    '@v-core/locale/shared.lua',
    'locales/en.lua',
    'locales/fr.lua',
    'config.lua',
    -- Drop-in apps. `_loader.lua` defines PhoneApp(); the glob after it picks up every
    -- app folder, so adding an app is adding a folder and nothing else.
    'apps/_loader.lua',
    'apps/*/app.lua',
}

client_scripts {
    'client/main.lua',
    'apps/*/client.lua',      -- optional, per app folder
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua',
    'apps/*/server.lua',      -- optional, per app folder
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/app.js',
    -- The app SDK. Served to any resource that ships a phone app, which is why it
    -- is a file rather than a copied snippet.
    'html/sdk.js',
    -- Everything a dropped-in app ships. The page and whatever it loads beside it.
    'apps/*/*.html',
    'apps/*/*.css',
    'apps/*/*.js',
    'apps/*/*.png',
    'apps/*/*.jpg',
    'apps/*/*.svg',
}
