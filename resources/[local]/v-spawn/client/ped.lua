-- v-spawn | ped appearance (natives)
local OVERLAYS = {
    eyebrows = { id = 2, colorType = 1 },
    beard    = { id = 1, colorType = 1 },
    makeup   = { id = 4, colorType = 2 },
    lipstick = { id = 8, colorType = 2 },
}

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
        components = {
            ['11'] = { drawable = (sex == 0 and 15 or 15), texture = 0 }, -- top / jacket
            ['8']  = { drawable = 15, texture = 0 },                       -- undershirt
            ['3']  = { drawable = 15, texture = 0 },                       -- arms
            ['4']  = { drawable = (sex == 0 and 21 or 15), texture = 0 },  -- pants
            ['6']  = { drawable = (sex == 0 and 34 or 35), texture = 0 },  -- shoes
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

--- Apply a full appearance table onto the local ped.
function ApplyAppearance(a)
    if not a then return end
    local ped = PlayerPedId()
    local hb = a.headBlend or {}
    SetPedHeadBlendData(ped,
        math.floor(hb.shapeFirst or 0), math.floor(hb.shapeSecond or 0), 0,
        math.floor(hb.skinFirst or 0), math.floor(hb.skinSecond or 0), 0,
        (hb.shapeMix or 0.5) + 0.0, (hb.skinMix or 0.5) + 0.0, 0.0, false)

    for i, v in pairs(a.faceFeatures or {}) do
        SetPedFaceFeature(ped, tonumber(i), (v or 0.0) + 0.0)
    end

    local hair = a.hair or {}
    SetPedComponentVariation(ped, 2, math.floor(hair.style or 0), 0, 0)
    SetPedHairColor(ped, math.floor(hair.color or 0), math.floor(hair.highlight or hair.color or 0))

    for key, def in pairs(OVERLAYS) do
        local o = (a.overlays or {})[key]
        if o then
            SetPedHeadOverlay(ped, def.id, math.floor(o.style or 0), (o.opacity or 0.0) + 0.0)
            SetPedHeadOverlayColor(ped, def.id, def.colorType, math.floor(o.color or 0), math.floor(o.color or 0))
        end
    end

    SetPedEyeColor(ped, math.floor(a.eyeColor or 0))

    for cid, c in pairs(a.components or {}) do
        SetPedComponentVariation(ped, tonumber(cid), math.floor(c.drawable or 0), math.floor(c.texture or 0), 0)
    end
end
