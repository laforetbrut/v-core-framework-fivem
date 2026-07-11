-- v-jobs | English
Locales.en = Locales.en or {}
local T = {
    ['jobs.paid']  = 'Salary: $%s.',
    ['jobs.set']   = 'Job set: %s — %s.',
    ['jobs.usage'] = 'Usage: setjob <playerId> <jobId> [grade].',
}
for k, v in pairs(T) do Locales.en[k] = v end
