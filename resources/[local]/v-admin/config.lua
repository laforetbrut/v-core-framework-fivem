-- v-admin | shared config
Config = {}

-- Permission required to open the panel; some actions need more.
Config.Permission = 'admin'
Config.SuperActions = { setperm = true, resource = true }   -- superadmin only

-- Weathers offered in the World tab (GTA V weather types).
Config.Weathers = {
    'EXTRASUNNY', 'CLEAR', 'CLOUDS', 'OVERCAST', 'RAIN', 'THUNDER',
    'CLEARING', 'FOGGY', 'SMOG', 'SNOWLIGHT', 'XMAS',
}

-- Resources that can never be stopped/restarted from the panel.
Config.ProtectedResources = {
    ['v-core'] = true, ['v-admin'] = true, ['oxmysql'] = true, ['v-ui'] = true,
}

-- Resource name prefixes listed in the Resources tab.
Config.ResourcePrefixes = { 'v-', 'oxmysql', 'screenshot-basic' }
