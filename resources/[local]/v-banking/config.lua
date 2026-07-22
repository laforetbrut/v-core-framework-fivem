-- v-banking | shared config
Config = {}

Config.Debug = false

-- ATM prop models players can use (GTA / Fleeca ATMs).
Config.AtmModels = {
    'prop_atm_01', 'prop_atm_02', 'prop_atm_03', 'prop_fleeca_atm',
}

-- Interaction.
Config.Distance = 1.4
Config.OpenControl = 38   -- E

-- How many transactions the UI shows.
Config.HistoryLimit = 20

-- Economy levers. A transfer fee is the framework's one built-in money sink; without
-- one, cash only ever moves sideways and never leaves the economy.
Config.TransferFee  = 0.0    -- fraction, e.g. 0.02 = 2% charged ON TOP of the amount
Config.MinTransfer  = 1      -- blocks $1 spam transfers used to bypass logging
Config.MaxTransfer  = 0      -- 0 = no ceiling
Config.MaxWithdraw  = 0      -- 0 = no ceiling, per single ATM withdrawal

-- What a debit card costs to order. It is not issued automatically: a card a character
-- never asked for is one more thing on their account they did not choose.
Config.CardFee = 250
