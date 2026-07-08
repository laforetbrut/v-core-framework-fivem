-- v-status | shared config
Config = {}

Config.Debug = false

-- Fresh-character defaults (0-100 for needs, bleed 0-4, sick 0-3).
Config.Defaults = { hunger = 100, thirst = 100, stress = 0, bleed = 0, sick = 0 }

-- Needs drain.
Config.NeedsTick = 60 * 1000            -- every minute
Config.Drain     = { hunger = 1.4, thirst = 2.0 }
Config.StarveDamage    = 4              -- HP lost per tick when a need hits 0
Config.NeedsFloorHealth = 110           -- needs never drop health below this (100 = dead)

-- Bleeding (injury). Higher level = faster blood loss.
Config.BleedTick   = 25 * 1000
Config.BleedDamage = { [1] = 2, [2] = 4, [3] = 7, [4] = 12 }
Config.BleedRagdollFrom = 3             -- levels >= this can ragdoll

-- Illness (sick 1-3): slow health/stamina toll.
Config.SickTick   = 90 * 1000
Config.SickDamage = { [1] = 1, [2] = 2, [3] = 4 }

-- Stress: screen effects thresholds.
Config.StressBlurFrom  = 70
Config.StressShakeFrom = 90
