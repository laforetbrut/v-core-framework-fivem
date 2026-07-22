-- v-3dsound | shared config
-- A primitive, not a feature. v-music, v-radio, v-housing, v-police and v-drugs all want
-- the same thing: play a sound at a place, heard by everyone near it. Building it once is
-- the whole point.
--
-- Two banks. **Native GTA sounds cost nothing** - no download, no streaming, already on
-- every client. A custom file is a download every player pays for, so prefer native and
-- reach for a file only when nothing in the game sounds right.
Config = {}

Config.MaxRange   = 120.0    -- ceiling on any caller's requested range
Config.MaxPerMin  = 30       -- per source, so a looping script cannot flood the server

-- name -> definition. `set` + `sound` is a native pair; `file` is a path under sounds/.
-- A definition may carry a default range and volume so callers do not repeat themselves.
Config.Bank = {
    -- interface / interaction
    click        = { set = 'HUD_MINI_GAME_SOUNDSET',        sound = 'CLICK_BACK',      range = 8.0 },
    confirm      = { set = 'HUD_FRONTEND_DEFAULT_SOUNDSET', sound = 'SELECT',          range = 10.0 },
    deny         = { set = 'HUD_FRONTEND_DEFAULT_SOUNDSET', sound = 'ERROR',           range = 10.0 },
    -- world
    cuff         = { set = 'HUD_MINI_GAME_SOUNDSET',        sound = 'CLICK_BACK',      range = 12.0 },
    lockpick     = { set = 'DLC_HEIST_FLEECA_SOUNDSET',     sound = 'SCREEN_FLOW',     range = 14.0 },
    dig          = { set = 'GTAO_Exec_SecuroServ_Computer_Sounds', sound = 'Beep',      range = 10.0 },
    money        = { set = 'HUD_FRONTEND_DEFAULT_SOUNDSET', sound = 'PURCHASE',        range = 6.0 },
    alarm        = { set = 'DLC_HEIST_HACKING_SNAKE_SOUNDS', sound = 'Highscore',      range = 60.0 },
    -- No custom files ship with the framework. Add one like this, drop the file in
    -- sounds/, and list it under `files` in fxmanifest.lua:
    --   siren = { file = 'sounds/siren.ogg', range = 90.0, volume = 0.8 },
}

-- Master volume applied to every custom (NUI) sound. Native sounds are mixed by the game.
Config.Volume = 0.7
