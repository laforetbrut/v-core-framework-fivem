Config = {}

Config.UseableItems = true -- Set to false if you want to use commands instead of usable items

Config.Locations = {
    ['main'] = {
        coords = vector4(-597.89, -929.95, 24.0, 271.5),
    },
    ['inside'] = {
        coords = vector4(-77.46, -833.77, 243.38, 67.5),
    },
    ['outside'] = {
        coords = vector4(-598.25, -929.86, 23.86, 86.5),
    },
    ['vehicle'] = {
        coords = vector4(-552.24, -925.61, 23.86, 242.5),
        vehicles = {
            [0] = {
                ['rumpo'] = { label = 'Rumpo', modLivery = 2 },
            },
            [1] = {
                ['rumpo'] = { label = 'Rumpo', modLivery = 2 },
            },
            [2] = {
                ['rumpo'] = { label = 'Rumpo', modLivery = 2 },
            },
            [3] = {
                ['rumpo'] = { label = 'Rumpo', modLivery = 2 },
            },
            [4] = {
                ['rumpo'] = { label = 'Rumpo', modLivery = 2 },
            },
        },
    },
    ['heli'] = {
        coords = vector4(-583.08, -930.55, 36.83, 89.26),
        vehicles = {
            [0] = {
                ['frogger'] = { label = 'Frogger' },
                ['conada'] = { label = 'Conada', modLivery = 5 },
            },
            [1] = {
                ['frogger'] = { label = 'Frogger' },
                ['conada'] = { label = 'Conada', modLivery = 5 },
            },
            [2] = {
                ['frogger'] = { label = 'Frogger' },
                ['conada'] = { label = 'Conada', modLivery = 5 },
            },
            [3] = {
                ['frogger'] = { label = 'Frogger' },
                ['conada'] = { label = 'Conada', modLivery = 5 },
            },
            [4] = {
                ['frogger'] = { label = 'Frogger' },
                ['conada'] = { label = 'Conada', modLivery = 5 },
            },
        },
    }
}

Config.VehicleItems = {
    [1] = {
        name = 'newscam',
        amount = 1,
        info = {},
    },
    [2] = {
        name = 'newsmic',
        amount = 1,
        info = {},
    },
    [3] = {
        name = 'newsbmic',
        amount = 1,
        info = {},
    },
}
