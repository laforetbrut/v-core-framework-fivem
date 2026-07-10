-- v-appearance | ped appearance engine (the SINGLE writer of the local ped)
--
-- Every resource that changes the player's look goes through these exports:
-- v-spawn (creator), v-clothing (store/equip), the barber/tattoo/surgery editors.
-- Components and props are stored as STABLE refs (see shared/refs.lua); this
-- engine also reads legacy v1 entries ({drawable,texture}) so old characters keep
-- rendering until the migration converts them.

local floor = math.floor

-- ── Head / face / hair / overlays / eyes ───────────────────────────
local function applyHead(ped, a)
    local hb = a.headBlend or {}
    SetPedHeadBlendData(ped,
        floor(hb.shapeFirst or 0), floor(hb.shapeSecond or 0), floor(hb.shapeThird or 0),
        floor(hb.skinFirst or 0), floor(hb.skinSecond or 0), floor(hb.skinThird or 0),
        (hb.shapeMix or 0.5) + 0.0, (hb.skinMix or 0.5) + 0.0, (hb.thirdMix or 0.0) + 0.0, false)

    for i, v in pairs(a.faceFeatures or {}) do
        SetPedFaceFeature(ped, tonumber(i), (v or 0.0) + 0.0)
    end

    local hair = a.hair or {}
    SetPedComponentVariation(ped, 2, floor(hair.style or 0), floor(hair.texture or 0), 0)
    SetPedHairColor(ped, floor(hair.color or 0), floor(hair.highlight or hair.color or 0))

    for key, def in pairs(Config.Overlays) do
        local o = (a.overlays or {})[key]
        if o then
            SetPedHeadOverlay(ped, def.id, floor(o.style or 0), (o.opacity or 0.0) + 0.0)
            if def.colorType then
                SetPedHeadOverlayColor(ped, def.id, def.colorType, floor(o.color or 0), floor(o.color2 or o.color or 0))
            end
        end
    end

    SetPedEyeColor(ped, floor(a.eyeColor or 0))
end

-- ── One component / prop slot ──────────────────────────────────────
local function isRef(c) return c and (c.idx ~= nil or c.col ~= nil) end

local function applyComponent(ped, id, c)
    if isRef(c) then
        if Refs.Apply(ped, 'comp', id, c) then return end
        -- ref invalid on this build: fall back to the legacy cache, then a default
        if c.drawable then
            SetPedComponentVariation(ped, id, floor(c.drawable), floor(c.texture or 0), 0)
        else
            SetPedComponentVariation(ped, id, Config.NudeDefaults[id] or 0, 0, 0)
        end
    else
        SetPedComponentVariation(ped, id, floor(c.drawable or 0), floor(c.texture or 0), 0)
    end
end

local function applyProp(ped, id, p)
    if isRef(p) then
        if Refs.Apply(ped, 'prop', id, p) then return end
        if (p.drawable or -1) < 0 then ClearPedProp(ped, id)
        elseif p.drawable then SetPedPropIndex(ped, id, floor(p.drawable), floor(p.texture or 0), true)
        else ClearPedProp(ped, id) end
    else
        if (p.drawable or -1) < 0 then ClearPedProp(ped, id)
        else SetPedPropIndex(ped, id, floor(p.drawable), floor(p.texture or 0), true) end
    end
end

-- ── Tattoos (ped decorations) ──────────────────────────────────────
-- Stored on the appearance as a.tattoos = { { c = collection, h = overlay }, ... }
-- (h is the gender-resolved overlay name, chosen when the tattoo was added).
-- MUST be applied AFTER SetPedHeadBlendData, which wipes decorations.
local function applyTattoos(ped, list)
    ClearPedDecorations(ped)
    for _, t in ipairs(list or {}) do
        if t.c and t.h then
            AddPedDecorationFromHashes(ped, joaat(t.c), joaat(t.h))
        end
    end
end

-- ── Full appearance apply ──────────────────────────────────────────
local function applyAppearance(a)
    if not a then return end
    local ped = PlayerPedId()
    applyHead(ped, a)
    for cid, c in pairs(a.components or {}) do applyComponent(ped, tonumber(cid), c) end
    for pid, p in pairs(a.props or {}) do applyProp(ped, tonumber(pid), p) end
    applyTattoos(ped, a.tattoos)
end

-- ── Capture the full current appearance off the live ped (as refs) ──
local function capture()
    local ped = PlayerPedId()
    local out = { schema = Config.Schema, components = {}, props = {} }
    for _, id in ipairs(Config.Components) do
        out.components[tostring(id)] = Refs.Capture(ped, 'comp', id)
    end
    for _, id in ipairs(Config.Props) do
        out.props[tostring(id)] = Refs.Capture(ped, 'prop', id)
    end
    return out
end

-- ── Height (experimental, off by default — Phase 5) ────────────────
-- No GTA V native scales a ped (SET_PED_SCALE is RDR3-only). The only technique
-- is a per-tick SET_ENTITY_MATRIX Z-scale, which is visual-only, does not resize
-- the collision capsule, and snaps back on vehicles/aiming/ragdoll. The real
-- matrix maths lands in Phase 5; for now SetHeight only records intent so the
-- rest of the engine and the persisted shape are ready. It applies nothing until
-- Config.Height.enabled is turned on and the Phase 5 applier is wired.
local heightScale = 1.0

-- ── Exports ────────────────────────────────────────────────────────
exports('ApplyAppearance', function(a) applyAppearance(a) end)
exports('GetCurrentAppearance', capture)

exports('ApplyRef', function(kind, compId, ref)
    local ped = PlayerPedId()
    if kind == 'prop' then applyProp(ped, compId, ref) else applyComponent(ped, compId, ref) end
    return true
end)

exports('RefFromGlobal', function(kind, compId, globalId, tex)
    return Refs.FromGlobal(PlayerPedId(), kind, compId, globalId, tex)
end)
exports('GlobalFromRef', function(kind, compId, ref)
    return Refs.ToGlobal(PlayerPedId(), kind, compId, ref)
end)
exports('RefValid', function(kind, compId, ref)
    return Refs.Valid(PlayerPedId(), kind, compId, ref)
end)
exports('CaptureRef', function(kind, compId)
    return Refs.Capture(PlayerPedId(), kind, compId)
end)
exports('TextureCountForRef', function(kind, compId, ref)
    return Refs.TextureCount(PlayerPedId(), kind, compId, ref)
end)

exports('SetHeight', function(scale)
    scale = tonumber(scale) or 1.0
    if scale < Config.Height.min then scale = Config.Height.min end
    if scale > Config.Height.max then scale = Config.Height.max end
    heightScale = scale
    -- Phase 5 wires the SET_ENTITY_MATRIX applier here (Config.Height.enabled gate).
end)

exports('ApplyTattoos', function(list) applyTattoos(PlayerPedId(), list) end)

-- Server can push a full re-apply (after a job-outfit change, an admin edit, ...)
RegisterNetEvent('v-appearance:client:apply', function(a) applyAppearance(a) end)
-- Server can push a single-slot re-apply (equip/unequip render)
RegisterNetEvent('v-appearance:client:applyRef', function(kind, compId, ref)
    local ped = PlayerPedId()
    if kind == 'prop' then applyProp(ped, compId, ref) else applyComponent(ped, compId, ref) end
end)
