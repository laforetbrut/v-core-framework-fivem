-- v-factions | shared config
-- The organisations themselves are NOT defined here: a faction is a row in `jobs` or in
-- `gangs`, both already editable from the admin panel. A legal faction and an illegal one
-- differ by data, not by code — which is the whole reason this layer exists rather than a
-- separate police module and a separate gang module with the same membership code twice.
Config = {}

-- Who counts as a boss when the grades JSON carries no explicit `isboss` flag. The seed
-- data predates the flag, so falling back to "the highest grade" keeps every existing
-- organisation working instead of leaving them all with no boss at all.
Config.BossFallbackHighestGrade = true

-- Treasury. A faction account is a real balance with its own audit trail, not a number in
-- a config: hiring, salaries, vehicle purchases and fines can all move through it.
Config.Treasury = {
    enabled       = true,
    startBalance  = 0,
    maxWithdraw   = 250000,   -- per single action; 0 = no ceiling
    allowNegative = false,    -- an overdrawn faction is a debt nobody can collect
    historyLimit  = 50,
}

-- Salaries paid FROM the treasury rather than minted. Off by default: turning it on is an
-- economic decision (an empty treasury then means nobody gets paid), not a default.
Config.SalaryFromTreasury = false

-- Kinds a faction can be. `job` reads the `jobs` table, `gang` reads `gangs`.
Config.Kinds = { 'job', 'gang' }
