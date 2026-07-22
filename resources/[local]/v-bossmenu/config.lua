-- v-bossmenu | shared config
-- The panel a faction leader needs. Gated on RANK, not on admin permission: an admin is
-- not a boss, and giving staff the boss menu is how a framework ends up with two ways to
-- move the same money.
Config = {}

-- No chat command: the menu opens on a keybind, like every other player-facing surface in
-- this framework. The key is rebindable by the player in the FiveM settings.
Config.Key = 'F6'

-- Hiring is done to a player standing in front of you, not to a citizen id typed from a
-- Discord message. The list is built server-side; the radius is what makes it roleplay.
Config.HireRadius = 6.0

-- What the menu is allowed to do. Each one is also a live setting.
Config.Allow = {
    hire        = true,
    fire        = true,
    promote     = true,
    treasury    = true,
    paySalaries = true,
}

-- Paying salaries by hand, from the treasury, for everyone currently on duty. Separate
-- from v-jobs' automatic loop: this is the boss choosing to pay, not the clock.
Config.SalaryMult = 1.0
