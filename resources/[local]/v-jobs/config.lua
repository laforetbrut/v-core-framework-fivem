-- v-jobs | shared config
-- Defines the valid jobs, their grades and salaries. Other modules gate access with
-- the job name (v-shops `shops.job`, v-inventory shared stashes, v-crafting recipe
-- gates). This is the single source of truth for what a job *is*.
Config = {}

-- Salary is paid to on-duty players every PayInterval minutes, into PayAccount.
Config.PayInterval = 10       -- minutes
Config.PayAccount  = 'bank'

-- job id -> { label, grades = { [n] = { name, salary } } }. Grade 0 is the base rank.
Config.Jobs = {
    unemployed = {
        label = 'Unemployed',
        grades = { [0] = { name = 'Civilian', salary = 0 } },
    },
    police = {
        label = 'Los Santos Police',
        grades = {
            [0] = { name = 'Cadet',      salary = 550 },
            [1] = { name = 'Officer',    salary = 750 },
            [2] = { name = 'Sergeant',   salary = 1000 },
            [3] = { name = 'Lieutenant', salary = 1350 },
            [4] = { name = 'Chief',      salary = 1800 },
        },
    },
    ambulance = {
        label = 'EMS',
        grades = {
            [0] = { name = 'Trainee',    salary = 500 },
            [1] = { name = 'Paramedic',  salary = 750 },
            [2] = { name = 'Doctor',     salary = 1100 },
            [3] = { name = 'Chief',      salary = 1600 },
        },
    },
    mechanic = {
        label = 'Mechanic',
        grades = {
            [0] = { name = 'Apprentice', salary = 400 },
            [1] = { name = 'Mechanic',   salary = 600 },
            [2] = { name = 'Manager',    salary = 900 },
        },
    },
    taxi = {
        label = 'Taxi',
        grades = {
            [0] = { name = 'Driver',     salary = 350 },
            [1] = { name = 'Dispatcher', salary = 550 },
        },
    },
}

-- New characters / job clears default to this.
Config.DefaultJob = 'unemployed'
