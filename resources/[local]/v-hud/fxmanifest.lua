fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'v-hud'
author 'vyrriox'
description 'v-hud — a fully player-configurable HUD: movable elements, five themes, ten speedometers, twenty-one dashboard tell-tales, compass, street names, compact and immersive modes (v-core module)'
version '1.0.1'

-- Detected by v-core's module registry (admin panel -> Settings). See DEVELOPERS.md.
v_module 'yes'
v_module_label 'Hud'
v_module_category 'gameplay'

-- v-core is the framework here, read through the bridge's own vcore adapter. v-status is
-- read at runtime for hunger/thirst when present. Everything else the bridge lists
-- (fuel, voice, sound providers) stays optional and runtime-detected; see config.lua ->
-- Config.Compat and bridge/{client/compat,server/framework}.lua.
dependency 'v-core'

shared_scripts {
    -- The bridge first: it defines HUD, the locale helper and the settings schema the rest
    -- of the resource is written against.
    'bridge/shared/hud.lua',
    'bridge/shared/locale.lua',

    -- English first: it is the fallback for any key missing from another locale file, so it
    -- is the base table the others are read against.
    'locales/en.lua',
    'locales/fr.lua',

    'config.lua',

    -- Themes and speedometers read Config, so they load after it. They are shared because the
    -- server validates a saved theme name against the same table the client offers.
    'shared/themes.lua',
    'shared/speedometers.lua',

    -- Drop-in themes. One file per theme, each defining `Themes.<key>`; see THEMES.md.
    --
    -- Listed by name rather than globbed with `themes/*.lua`, and that is deliberate. A glob
    -- that matches nothing prints a warning on every restart, and a glob does not resolve at
    -- all when the resource is installed as a junction to a git checkout - which is how
    -- anybody developing against it runs it. One line per theme is the cost.
    'themes/example.lua',
    -- Merge/validate a settings payload. Shared because the client applies it and the server
    -- re-validates it: one implementation, no drift.
    'shared/settings.lua',
}

client_scripts {
    -- Runtime detection of everything optional. FIRST, because every client file below asks
    -- it what is installed.
    'bridge/client/compat.lua',
    'client/settings.lua',
    'client/minimap.lua',
    'client/compass.lua',
    'client/vehicle.lua',
    -- Before client/vehicle.lua would be wrong: the odometer is read BY the vehicle reader,
    -- but only at runtime, and this file's own loop needs State from client/settings.lua.
    'client/odometer.lua',
    'client/stress.lua',
    -- Feeds the vitals rings from v-status, the framework's owner of hunger/thirst/stress.
    -- After client/stress.lua, whose Needs channel it writes into.
    'client/vstatus.lua',
    'client/main.lua',
    'client/commands.lua',
}

server_scripts {
    'bridge/server/framework.lua',
    'server/storage.lua',
    'server/main.lua',
    'server/stress.lua',
    'server/odometer.lua',
    'server/admin.lua',
}

ui_page 'html/index.html'

-- No `stream/` folder. The square-minimap masks (squaremap/circlemap/minimap .ytd) are the
-- community qb-hud set, and the default game build rejects them as an asset version
-- mismatch - and this framework does not pin a game build. So the minimap defaults to the
-- native round shape (config.lua -> Config.Defaults.minimap.shape), which needs no mask.
-- client/minimap.lua already degrades gracefully: it warns once and keeps the game shape
-- when a mask is not streaming. A server that pins a build can drop the four ytd/gfx files
-- into a stream/ folder and switch the default back to 'square'.

files {
    'html/index.html',
    'html/css/reset.css',
    'html/css/hud.css',
    'html/css/status.css',
    'html/css/speedo.css',
    'html/css/menu.css',
    'html/css/themes.css',
    'html/js/util.js',
    'html/js/state.js',
    'html/js/status.js',
    'html/js/speedo.js',
    'html/js/compass.js',
    'html/js/toast.js',
    'html/js/sound.js',
    'html/js/layout.js',
    'html/js/menu.js',
    'html/js/app.js',
}
