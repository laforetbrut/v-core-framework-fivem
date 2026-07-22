fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'v-vehicles'
author 'vyrriox'
description 'v-vehicles — owned-vehicle persistence, server-minted plates and the key system (v-core module)'
version '0.1.0'

-- Detected by v-core's module registry (admin panel -> Settings). See DEVELOPERS.md.
v_module 'yes'
v_module_label 'Vehicles'
v_module_category 'vehicles'
dependencies {
    'v-core',
    'oxmysql',
}

shared_scripts {
    '@v-core/locale/shared.lua',
    'locales/en.lua',
    'locales/fr.lua',
    'config.lua',
}

client_scripts {
    'client/main.lua',
    'client/preview.lua',   -- showroom instance (shared by v-garages and the dealership)
    'client/seatbelt.lua',  -- seatbelt + windscreen ejection
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua',
}
