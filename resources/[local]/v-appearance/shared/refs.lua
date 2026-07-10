-- v-appearance | stable clothing references (client-only natives)
--
-- A garment's raw *global* drawable id is its position across base game + every
-- streamed DLC/addon in the current load order, so adding or reordering a pack
-- changes what an id points at. The ped-collection natives decompose that global
-- id into a STABLE (collection name, local index, texture) tuple that survives
-- addon/replace clothing and game-build changes.
--
--   ref = { col = <collection name, '' for base game>, idx = <local index>, tex = <texture> }
--
-- All natives below are client-side; this file loads as a client_script.

Refs = {}

-- capture what the ped is CURRENTLY wearing on a slot as a stable ref
function Refs.Capture(ped, kind, compId)
    if kind == 'prop' then
        local drawable = GetPedPropIndex(ped, compId)
        if drawable < 0 then return { col = Config.BaseCollection, idx = -1, tex = 0 } end
        return {
            col = GetPedPropCollectionName(ped, compId) or Config.BaseCollection,
            idx = GetPedPropCollectionLocalIndex(ped, compId),
            tex = GetPedPropTextureIndex(ped, compId),
        }
    end
    return {
        col = GetPedDrawableVariationCollectionName(ped, compId) or Config.BaseCollection,
        idx = GetPedDrawableVariationCollectionLocalIndex(ped, compId),
        tex = GetPedTextureVariation(ped, compId),
    }
end

-- decompose a known global drawable/prop id into a stable ref.
--   globalId < 0            -> genuine "none" (idx = -1)
--   decode fails (native -1)-> invalid ref (idx = nil), so callers fall back to
--                              the legacy drawable instead of blanking the garment
function Refs.FromGlobal(ped, kind, compId, globalId, tex)
    tex = tex or 0
    if globalId == nil or globalId < 0 then
        return { col = Config.BaseCollection, idx = -1, tex = tex }
    end
    local col, idx
    if kind == 'prop' then
        col = GetPedCollectionNameFromProp(ped, compId, globalId) or Config.BaseCollection
        idx = GetPedCollectionLocalIndexFromProp(ped, compId, globalId)
    else
        col = GetPedCollectionNameFromDrawable(ped, compId, globalId) or Config.BaseCollection
        idx = GetPedCollectionLocalIndexFromDrawable(ped, compId, globalId)
    end
    if idx == nil or idx < 0 then
        return { col = Config.BaseCollection, idx = nil, tex = tex }   -- undecodable -> invalid
    end
    return { col = col, idx = idx, tex = tex }
end

-- resolve a stable ref back to a global id for the CURRENT load order (-1 if absent)
function Refs.ToGlobal(ped, kind, compId, ref)
    if not ref or (ref.idx or -1) < 0 then return -1 end
    if kind == 'prop' then
        return GetPedPropGlobalIndexFromCollection(ped, compId, ref.col or Config.BaseCollection, ref.idx)
    end
    return GetPedDrawableGlobalIndexFromCollection(ped, compId, ref.col or Config.BaseCollection, ref.idx)
end

-- is a ref valid on THIS build (collection present, index in range)?
--   idx == nil -> undecodable, invalid (caller falls back to the legacy drawable)
--   idx  <  0  -> "none": valid only for props (ClearPedProp); a component has no
--                 "none" state (a bare slot is drawable 0, not -1)
function Refs.Valid(ped, kind, compId, ref)
    if not ref or ref.idx == nil then return false end
    if ref.idx < 0 then return kind == 'prop' end
    local col = ref.col or Config.BaseCollection
    local n = (kind == 'prop')
        and GetNumberOfPedCollectionPropDrawableVariations(ped, compId, col)
        or  GetNumberOfPedCollectionDrawableVariations(ped, compId, col)
    return n > 0 and ref.idx < n
end

-- apply a stable ref to the ped. Returns true if applied, false if the ref is
-- invalid on this build (caller may fall back to a legacy drawable or a default).
function Refs.Apply(ped, kind, compId, ref)
    if not Refs.Valid(ped, kind, compId, ref) then return false end
    if kind == 'prop' then
        if (ref.idx or -1) < 0 then
            ClearPedProp(ped, compId)
        else
            SetPedCollectionPropIndex(ped, compId, ref.col or Config.BaseCollection, ref.idx, ref.tex or 0, true)
        end
    else
        SetPedCollectionComponentVariation(ped, compId, ref.col or Config.BaseCollection, ref.idx, ref.tex or 0, 0)
    end
    return true
end

-- texture count for a ref's drawable on this build
function Refs.TextureCount(ped, kind, compId, ref)
    if not ref or (ref.idx or -1) < 0 then return 0 end
    local col = ref.col or Config.BaseCollection
    if kind == 'prop' then
        return GetNumberOfPedCollectionPropTextureVariations(ped, compId, col, ref.idx)
    end
    return GetNumberOfPedCollectionTextureVariations(ped, compId, col, ref.idx)
end
