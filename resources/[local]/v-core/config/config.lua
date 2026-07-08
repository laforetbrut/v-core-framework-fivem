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
