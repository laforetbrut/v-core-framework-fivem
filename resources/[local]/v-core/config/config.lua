-- v-core | shared config
Config = {}

Config.Debug      = true
Config.ServerName = 'Projet R'

-- Default spawn used until a character system takes over (LSIA parking).
Config.DefaultSpawn = vector4(-1037.66, -2737.98, 20.17, 329.3)

-- Money accounts a character owns.
Config.Accounts = { 'cash', 'bank' }

-- Balances given to a brand-new character.
Config.StartingMoney = {
    cash = 500,
    bank = 5000,
}

-- Autosave every player to the database on this interval (ms).
Config.SaveInterval = 5 * 60 * 1000

-- Permission tiers (higher = more power). Used to gate in-game management.
Config.PermissionLevels = {
    user       = 0,
    mod        = 1,
    admin      = 2,
    superadmin = 3,
}

-- How many character slots each permission tier gets on the selection screen.
Config.CharacterSlots = {
    user       = 1,
    mod        = 2,
    admin      = 6,
    superadmin = 6,
}

-- Which tiers may delete one of their own characters from the selection screen.
Config.CanDeleteCharacter = { admin = true, superadmin = true }

-- Bootstrap admins by license (applied on join, before the DB value).
-- Find your license in the server console when you connect, then add it here:
Config.Admins = {
    -- ['license:xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx'] = 'superadmin',
}
