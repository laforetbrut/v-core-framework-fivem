-- v-factions | English
Locales.en = Locales.en or {}
local T = {
    ['fac.treasury']      = 'Treasury',
    ['fac.balance']       = 'Balance',
    ['fac.deposit']       = 'Deposit',
    ['fac.withdraw']      = 'Withdraw',
    ['fac.salary']        = 'Salary',
    ['fac.members']       = 'Members',
    ['fac.boss']          = 'Boss',
    ['fac.hired']         = 'Hired.',
    ['fac.fired']         = 'Dismissed.',
    ['fac.graded']        = 'Rank changed.',
    ['fac.paid']          = 'Salary paid from the treasury.',
    ['fac.nopay']         = 'The treasury could not cover the salaries.',
    ['fac.err_rank']      = 'Your rank does not allow that.',
    ['fac.err_faction']   = 'That organisation does not exist.',
    ['fac.err_target']    = 'Member not found.',
    ['fac.err_grade']     = 'That rank does not exist.',
    ['fac.err_funds']     = 'The treasury does not have enough.',
    ['fac.err_limit']     = 'That is over the withdrawal limit.',
    ['fac.err_amount']    = 'Enter an amount.',
    ['fac.err_disabled']  = 'Treasuries are disabled on this server.',
}
for k, v in pairs(T) do Locales.en[k] = v end
