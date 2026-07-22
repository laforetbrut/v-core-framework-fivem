-- v-spawn | ped appearance
-- Rendering is delegated to the v-appearance engine (the single ped writer).
-- This file keeps only creation-specific helpers: default appearance + model swap.

--- Fresh default appearance for a sex (0 male, 1 female).
function DefaultAppearance(sex)
    sex = sex or 0
    return {
        sex = sex,
        headBlend    = { shapeFirst = 0, shapeSecond = 0, skinFirst = 0, skinSecond = 0, shapeMix = 0.5, skinMix = 0.5 },
        faceFeatures = {},
        hair         = { style = 0, color = 0, highlight = 0 },
        overlays     = {
            eyebrows = { style = 0, opacity = 1.0, color = 0 },
            beard    = { style = 0, opacity = 1.0, color = 0 },
            makeup   = { style = 0, opacity = 0.0, color = 0 },
            lipstick = { style = 0, opacity = 0.0, color = 0 },
        },
        eyeColor   = 0,
        -- Every clothing slot the engine knows about is listed explicitly, including the
        -- ones the store now sells (bag / neck / armor / decal). SetPedDefaultComponentVariation
        -- hands out a RANDOM outfit, so a slot left unset here would leak a random bag,
        -- chain or badge onto a brand-new character.
        components = {
            ['1']  = { drawable = 0, texture = 0 },                        -- mask (0 = none)
            ['3']  = { drawable = 15, texture = 0 },                       -- arms / gloves
            ['4']  = { drawable = (sex == 0 and 21 or 15), texture = 0 },  -- pants
            ['5']  = { drawable = 0, texture = 0 },                        -- bag / parachute (none)
            ['6']  = { drawable = (sex == 0 and 34 or 35), texture = 0 },  -- shoes
            ['7']  = { drawable = 0, texture = 0 },                        -- neck / chain (none)
            ['8']  = { drawable = 15, texture = 0 },                       -- undershirt
            ['9']  = { drawable = 0, texture = 0 },                        -- body armor (none)
            ['10'] = { drawable = 0, texture = 0 },                        -- decals / badges (none)
            ['11'] = { drawable = 15, texture = 0 },                       -- top / jacket
        },
        props = {
            ['0'] = { drawable = -1, texture = 0 },   -- hat (-1 = none)
            ['1'] = { drawable = -1, texture = 0 },   -- glasses
            ['2'] = { drawable = -1, texture = 0 },   -- earrings
            ['6'] = { drawable = -1, texture = 0 },   -- watch
            ['7'] = { drawable = -1, texture = 0 },   -- bracelet
        },
    }
end

--- Switch the player's freemode model.
function SetSexModel(sex)
    local model = Config.Models[sex] or Config.Models[0]
    local hash = joaat(model)
    RequestModel(hash)
    local tries = 0
    while not HasModelLoaded(hash) and tries < 100 do Wait(30); tries = tries + 1 end
    SetPlayerModel(PlayerId(), hash)
    SetPedDefaultComponentVariation(PlayerPedId())
    SetModelAsNoLongerNeeded(hash)
end

--- Apply a full appearance table onto the local ped (delegates to the engine).
function ApplyAppearance(a)
    exports['v-appearance']:ApplyAppearance(a)
end
