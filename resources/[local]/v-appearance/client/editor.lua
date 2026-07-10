-- v-appearance | shared appearance editor (barber / surgery / tattoo)
-- Reads the character's stored appearance, edits a working copy with a live
-- preview through the engine, and saves via v-core on confirm (reverts on close).
local isOpen  = false
local mode    = nil
local work    = nil     -- working appearance copy (live-previewed)
local snapshot = nil    -- revert copy

local function strings()
    return Locales[(LocalPlayer.state and LocalPlayer.state.lang) or 'fr'] or Locales.fr or {}
end
local function clone(t) return json.decode(json.encode(t or {})) end

local function currentAppearance()
    local pd = exports['v-core']:GetPlayerData()
    return (pd and pd.appearance) or {}
end

local function applyWork()
    exports['v-appearance']:ApplyAppearance(work)
end

-- ── NUI data per mode ──────────────────────────────────────────────
local function barberData(ped)
    local ov = {}
    for _, key in ipairs(Config.BarberOverlays) do
        local def = Config.Overlays[key]
        if def then
            ov[#ov + 1] = { key = key, id = def.id, colorType = def.colorType,
                            count = GetPedHeadOverlayNum(def.id) }
        end
    end
    return {
        hairCount    = GetNumberOfPedDrawableVariations(ped, 2),
        hairColors   = GetNumHairColors(),
        makeupColors = GetNumMakeupColors(),
        overlays     = ov,
    }
end

local function surgeryData()
    return { features = Config.FaceFeatures }
end

local function tattooData()
    local sex = work.sex or 0
    local out = {}   -- zone -> [{ name, label, c, h }]
    for zone, list in pairs(AppearanceTattoos or {}) do
        local z = {}
        for _, t in ipairs(list) do
            z[#z + 1] = { name = t.name, label = t.label, zone = zone,
                          c = t.collection, h = (sex == 0 and t.hashMale or t.hashFemale) }
        end
        out[zone] = z
    end
    return { sex = sex, zones = out, applied = work.tattoos or {} }
end

-- ── Open / close ────────────────────────────────────────────────────
function OpenEditor(m)
    if isOpen then return end
    if m ~= 'barber' and m ~= 'surgery' and m ~= 'tattoo' then return end
    mode = m
    snapshot = clone(currentAppearance())
    work = clone(snapshot)
    work.hair         = work.hair or { style = 0, color = 0, highlight = 0 }
    work.overlays     = work.overlays or {}
    work.faceFeatures = work.faceFeatures or {}
    work.headBlend    = work.headBlend or {}
    work.tattoos      = work.tattoos or {}

    isOpen = true
    SetNuiFocus(true, true)
    exports['v-core']:MenuOpened()
    EditorCamStart()

    local ped = PlayerPedId()
    local data = { mode = m, appearance = work, strings = strings() }
    if m == 'barber' then for k, v in pairs(barberData(ped)) do data[k] = v end
    elseif m == 'surgery' then for k, v in pairs(surgeryData()) do data[k] = v end
    else for k, v in pairs(tattooData()) do data[k] = v end end
    SendNUIMessage({ action = 'open', data = data })
end

local function finish(save)
    isOpen = false
    SetNuiFocus(false, false)
    exports['v-core']:MenuClosed()
    EditorCamStop()
    SendNUIMessage({ action = 'close' })
    if save then
        exports['v-appearance']:ApplyAppearance(work)
        TriggerServerEvent('v-core:server:saveAppearance', work)
    else
        exports['v-appearance']:ApplyAppearance(snapshot)   -- revert live preview
    end
    work, snapshot, mode = nil, nil, nil
end

-- ── NUI callbacks ───────────────────────────────────────────────────
RegisterNUICallback('appSetHair', function(data, cb)
    work.hair.style     = tonumber(data.style)     or work.hair.style
    work.hair.color     = tonumber(data.color)     or work.hair.color
    work.hair.highlight = tonumber(data.highlight) or work.hair.highlight
    applyWork(); cb('ok')
end)

RegisterNUICallback('appSetOverlay', function(data, cb)
    local key = data.key
    if not key then cb(false); return end
    local o = work.overlays[key] or { style = 0, opacity = 1.0, color = 0 }
    if data.style   ~= nil then o.style   = tonumber(data.style) end
    if data.opacity ~= nil then o.opacity = tonumber(data.opacity) + 0.0 end
    if data.color   ~= nil then o.color   = tonumber(data.color) end
    work.overlays[key] = o
    applyWork(); cb('ok')
end)

RegisterNUICallback('appSetFace', function(data, cb)
    local id = tostring(tonumber(data.id))
    work.faceFeatures[id] = (tonumber(data.value) or 0.0) + 0.0
    applyWork(); cb('ok')
end)

RegisterNUICallback('appSetBlend', function(data, cb)
    if data.shapeMix ~= nil then work.headBlend.shapeMix = tonumber(data.shapeMix) + 0.0 end
    if data.skinMix  ~= nil then work.headBlend.skinMix  = tonumber(data.skinMix) + 0.0 end
    applyWork(); cb('ok')
end)

RegisterNUICallback('appAddTattoo', function(data, cb)
    if data.c and data.h then
        -- de-dupe, then keep only one tattoo per zone-collection is not required;
        -- allow multiple but avoid exact duplicates.
        for _, t in ipairs(work.tattoos) do if t.c == data.c and t.h == data.h then cb('ok'); return end end
        work.tattoos[#work.tattoos + 1] = { c = data.c, h = data.h }
        applyWork()
    end
    cb('ok')
end)

RegisterNUICallback('appRemoveTattoo', function(data, cb)
    for i, t in ipairs(work.tattoos) do
        if t.c == data.c and t.h == data.h then table.remove(work.tattoos, i); break end
    end
    applyWork(); cb('ok')
end)

RegisterNUICallback('appClearTattoos', function(_, cb)
    work.tattoos = {}
    applyWork(); cb('ok')
end)

RegisterNUICallback('appCam', function(data, cb)
    if data.orbit then EditorCamOrbit(data.orbit) end
    if data.zone then EditorCamZone(data.zone) end
    cb('ok')
end)

RegisterNUICallback('appConfirm', function(_, cb) cb('ok'); finish(true) end)
RegisterNUICallback('appClose',   function(_, cb) cb('ok'); finish(false) end)

exports('OpenEditor', function(m) OpenEditor(m) end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    if isOpen then SetNuiFocus(false, false); exports['v-core']:MenuClosed(); EditorCamStop() end
end)
