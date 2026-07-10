-- v-clothing | client
local Core = exports['v-core']:GetCore()
local isOpen  = false
local spawned = {}
local preview = {}     -- category key -> { drawable, texture }
local savedApp = nil   -- appearance snapshot to revert previews on close

local CatByKey = {}
for _, c in ipairs(Config.Categories) do CatByKey[c.key] = c end

local function strings()
    return Locales[(LocalPlayer.state and LocalPlayer.state.lang) or 'fr'] or Locales.fr or {}
end

local function wrap(v, lo, hi) if v < lo then return hi elseif v > hi then return lo else return v end end

local function applyToPed(m)
    local ped = PlayerPedId()
    if m.kind == 'comp' then
        SetPedComponentVariation(ped, m.id, math.floor(m.drawable), math.floor(m.texture or 0), 0)
    else
        if m.off or (m.drawable or -1) < 0 then ClearPedProp(ped, m.id)
        else SetPedPropIndex(ped, m.id, math.floor(m.drawable), math.floor(m.texture or 0), true) end
    end
end

-- ── Store camera (front view, mouse-drag rotate) ──────────────
local storeCam = nil
local camHeading = 0.0

local function updateCam()
    if not storeCam then return end
    local ped = PlayerPedId()
    local c = GetEntityCoords(ped)
    local rad = math.rad(GetEntityHeading(ped) + camHeading)
    SetCamCoord(storeCam, c.x - math.sin(rad) * 1.7, c.y + math.cos(rad) * 1.7, c.z + 0.25)
    PointCamAtCoord(storeCam, c.x, c.y, c.z + 0.05)
end

local function startCam()
    storeCam = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA', 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 42.0, false, 0)
    SetCamActive(storeCam, true)
    RenderScriptCams(true, false, 0, true, false)
    camHeading = 0.0
    updateCam()
end

local function stopCam()
    RenderScriptCams(false, false, 0, true, false)
    if storeCam then DestroyCam(storeCam, false); storeCam = nil end
end

-- current value on the ped for a category
local function current(cat)
    local ped = PlayerPedId()
    if cat.kind == 'comp' then
        return { drawable = GetPedDrawableVariation(ped, cat.id), texture = GetPedTextureVariation(ped, cat.id) }
    end
    return { drawable = GetPedPropIndex(ped, cat.id), texture = GetPedPropTextureIndex(ped, cat.id) }
end

-- ── Equip / unequip application (persisted) ────────────────────
-- The server sends a global drawable/texture; we render it, then capture the
-- STABLE (collection,index,texture) ref from the ped via the v-appearance engine
-- and persist THAT, so worn clothing survives addon/build changes (schema v2).
RegisterNetEvent('v-clothing:client:apply', function(m)
    applyToPed(m)
    local kind = (m.kind == 'comp') and 'comp' or 'prop'
    local ref = exports['v-appearance']:CaptureRef(kind, m.id)
    local pd = exports['v-core']:GetPlayerData()
    local app = (pd and pd.appearance) or {}
    app.components = app.components or {}; app.props = app.props or {}
    app.schema = 2
    local entry = { col = ref.col, idx = ref.idx, tex = ref.tex, drawable = m.drawable, texture = m.texture or 0 }
    if kind == 'comp' then
        app.components[tostring(m.id)] = entry
    else
        if m.off then entry = { col = '', idx = -1, tex = 0, drawable = -1, texture = 0 } end
        app.props[tostring(m.id)] = entry
    end
    TriggerServerEvent('v-core:server:saveAppearance', app)
end)

-- ════════════════════════════════════════════════════════════════
--  Thumbnail scan (admin) — dress the ped in every drawable, capture it
-- ════════════════════════════════════════════════════════════════
local scanning = false

local function placeScanCam(cam, ped, fr, skyTilt)
    local at = GetPedBoneCoords(ped, fr.bone, 0.0, 0.0, 0.0)
    local h  = math.rad(GetEntityHeading(ped))
    local fx, fy = -math.sin(h), math.cos(h)          -- ped forward vector
    local lift = skyTilt and (fr.dist * 0.28) or 0.0  -- shoot from slightly below -> sky-only background
    SetCamCoord(cam, at.x + fx * fr.dist, at.y + fy * fr.dist, at.z + fr.height - lift)
    PointCamAtCoord(cam, at.x, at.y, at.z + fr.atZ)
    SetCamFov(cam, fr.fov)
end

-- Re-apply a saved slot, preferring the stable ref via the engine and falling
-- back to the legacy global cache for pre-migration data.
local function applySaved(c, saved)
    if saved and (saved.idx ~= nil or saved.col ~= nil) then
        exports['v-appearance']:ApplyRef(c.kind, c.id, saved)
    elseif saved then
        applyToPed({ kind = c.kind, id = c.id, drawable = saved.drawable, texture = saved.texture or 0, off = (c.kind == 'prop' and (saved.drawable or -1) < 0) })
    else
        applyToPed({ kind = c.kind, id = c.id, drawable = Config.NudeDefaults[c.id] or 0, texture = 0, off = (c.kind == 'prop') })
    end
end

local function restoreSlots(snap)
    for _, c in ipairs(Config.Categories) do
        local saved = snap and (c.kind == 'comp'
            and (snap.components or {})[tostring(c.id)]
            or  (snap.props or {})[tostring(c.id)])
        applySaved(c, saved)
    end
end

local function capture()
    local p, ok = promise.new()
    ok = pcall(function()
        exports['screenshot-basic']:requestScreenshot(
            { encoding = 'jpg', quality = 0.92 },   -- high-quality source; the NUI isolates & downscales
            function(data) p:resolve(data) end)
    end)
    if not ok then return nil end
    return Citizen.Await(p)
end

-- Ship one piece to the server THROUGH THE NUI: it diffs the bare/dressed
-- shots to keep only the garment (transparent background), crops it, then
-- HTTP-uploads the result. Never TriggerServerEvent with an image: large
-- net events trip FiveM's reliable-event overflow protection and kick.
local processP = nil
RegisterNUICallback('thumbDone', function(data, cb)
    if processP then local p = processP; processP = nil; p:resolve(data and data.ok or false) end
    cb('ok')
end)

local function processThumb(endpoint, token, catKey, d, baseUri, itemUri)
    processP = promise.new()
    local p = processP
    SetTimeout(20000, function() if processP == p then processP = nil; p:resolve(false) end end)
    SendNUIMessage({
        action = 'processThumb', endpoint = endpoint, res = GetCurrentResourceName(),
        token = token, cat = catKey, drawable = d,
        base = baseUri, item = itemUri,
        size = Config.Thumbs.size, format = Config.Thumbs.format, quality = Config.Thumbs.quality,
        diffMin = Config.Thumbs.diffMin, diffMax = Config.Thumbs.diffMax, pad = Config.Thumbs.pad,
    })
    return Citizen.Await(p)
end

-- Bare (nude/empty) state for one slot — the isolation baseline.
local function applyBare(c)
    applyToPed({ kind = c.kind, id = c.id, drawable = Config.NudeDefaults[c.id] or 0, texture = 0, off = (c.kind == 'prop') })
end

-- "Studio": frozen noon, no clouds/wind/fidgets, isolated sky point — the two
-- shots of a pair then differ ONLY by the garment. Returns a restore closure.
local function enterStudio(ped)
    local pos, heading = GetEntityCoords(ped), GetEntityHeading(ped)
    local h, m, s = GetClockHours(), GetClockMinutes(), GetClockSeconds()
    local clouds = 0.0
    pcall(function() clouds = GetCloudHatOpacity() end)
    FreezeEntityPosition(ped, true)
    ClearPedTasksImmediately(ped)
    pcall(function() SetPedCanPlayAmbientAnims(ped, false) end)
    if Config.Thumbs.studio then
        SetEntityCoordsNoOffset(ped, Config.Thumbs.studio.x, Config.Thumbs.studio.y, Config.Thumbs.studio.z, false, false, false)
        SetEntityHeading(ped, 180.0)
    end
    NetworkOverrideClockTime(12, 0, 0)
    PauseClock(true)
    pcall(function() SetOverrideWeather('EXTRASUNNY') end)
    pcall(function() SetWind(0.0) end)
    pcall(function() SetCloudHatOpacity(0.0) end)
    Wait(400)   -- let streaming / lighting settle
    return function()
        if Config.Thumbs.studio then
            SetEntityCoordsNoOffset(ped, pos.x, pos.y, pos.z, false, false, false)
            SetEntityHeading(ped, heading)
        end
        PauseClock(false)
        NetworkOverrideClockTime(h, m, s)
        pcall(function() NetworkClearClockTimeOverride() end)
        pcall(function() ClearOverrideWeather() end)
        pcall(function() SetCloudHatOpacity(clouds) end)
        pcall(function() SetPedCanPlayAmbientAnims(ped, true) end)
        FreezeEntityPosition(ped, false)
    end
end

RegisterNetEvent('v-clothing:client:startScan', function(mode, onlyCat, token)
    if scanning then return end
    local endpoint = GetCurrentServerEndpoint()
    if GetResourceState('screenshot-basic') ~= 'started' or not endpoint or not token then
        TriggerServerEvent('v-clothing:server:scanDone', 0)   -- capture tool missing / no upload route
        return
    end
    scanning = true
    CreateThread(function()
        local ped  = PlayerPedId()
        local pd   = exports['v-core']:GetPlayerData()
        local snap = pd and pd.appearance and json.decode(json.encode(pd.appearance)) or {}
        local isolate = Config.Thumbs.isolate

        -- clean scene
        DisplayRadar(false)
        local leaveStudio = enterStudio(ped)
        -- strip every slot: each piece is shot on a bare body
        if isolate then for _, c in ipairs(Config.Categories) do applyBare(c) end end
        local cam = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA', 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 42.0, false, 0)
        SetCamActive(cam, true)
        RenderScriptCams(true, false, 0, true, false)
        CreateThread(function() while scanning do HideHudAndRadarThisFrame(); Wait(0) end end)

        -- categories to scan
        local targets = {}
        for _, c in ipairs(Config.Categories) do
            if not onlyCat or onlyCat == c.key then targets[#targets + 1] = c end
        end

        -- already-generated thumbs (for 'new' mode)
        local existing = {}
        if mode == 'new' then
            for _, c in ipairs(targets) do
                local pr = promise.new()
                Core.TriggerCallback('v-clothing:thumbIndex', function(list) pr:resolve(list or {}) end, c.key)
                existing[c.key] = {}
                for _, d in ipairs(Citizen.Await(pr)) do existing[c.key][d] = true end
            end
        end

        local function wanted(cKey, d) return not (mode == 'new' and existing[cKey] and existing[cKey][d]) end

        -- total (for progress)
        local total = 0
        for _, c in ipairs(targets) do
            local n = (c.kind == 'comp') and GetNumberOfPedDrawableVariations(ped, c.id) or GetNumberOfPedPropDrawableVariations(ped, c.id)
            for d = 0, n - 1 do if wanted(c.key, d) then total = total + 1 end end
        end

        SendNUIMessage({ action = 'scanUI', phase = 'start',
            title = strings()['cl.scan_title'] or 'Clothing scan', total = total })

        local done, fails = 0, 0
        for _, c in ipairs(targets) do
            local fr = Config.Framing[Config.CatFraming[c.key] or 'body']
            local n  = (c.kind == 'comp') and GetNumberOfPedDrawableVariations(ped, c.id) or GetNumberOfPedPropDrawableVariations(ped, c.id)
            for d = 0, n - 1 do
                if scanning and wanted(c.key, d) then
                    placeScanCam(cam, ped, fr, Config.Thumbs.studio ~= false)
                    -- shot A: bare slot (isolation baseline)
                    local baseUri = nil
                    if isolate then
                        applyBare(c)
                        Wait(Config.Thumbs.streamWait)
                        baseUri = capture()
                    end
                    -- shot B: the piece
                    applyToPed({ kind = c.kind, id = c.id, drawable = d, texture = 0, off = false })
                    Wait(Config.Thumbs.streamWait)
                    local itemUri = capture()
                    local sent = itemUri and processThumb(endpoint, token, c.key, d, baseUri, itemUri) or false
                    if sent then done = done + 1; fails = 0 else fails = fails + 1 end
                    SendNUIMessage({ action = 'scanUI', phase = 'item',
                        label = strings()[c.i18n] or c.key, done = done, total = total, ok = sent })
                    if fails >= 8 then    -- upload route is dead: bail instead of looping for nothing
                        scanning = false
                        Core.Notify(strings()['cl.scan_abort'] or 'Scan aborted (upload failed).', 'error')
                    end
                    if done > 0 and done % Config.Thumbs.notifyEvery == 0 then
                        TriggerServerEvent('v-clothing:server:scanProgress', done, total)
                    end
                    Wait(0)
                end
            end
            if isolate then applyBare(c) end   -- strip this category before the next one
        end

        -- restore
        SendNUIMessage({ action = 'scanUI', phase = 'done', done = done, total = total })
        RenderScriptCams(false, false, 0, true, false)
        DestroyCam(cam, false)
        restoreSlots(snap)
        leaveStudio()
        DisplayRadar(true)
        scanning = false
        TriggerServerEvent('v-clothing:server:scanDone', done)
    end)
end)

-- Admin keybind (this server has no chat): F9 twice within 5s starts a scan
-- of the missing thumbnails ('new' mode). Rebindable in GTA key settings.
local scanArmedAt = 0
RegisterCommand('vclothing_scan', function()
    if scanning or isOpen then return end
    local now = GetGameTimer()
    if now - scanArmedAt < 5000 then
        scanArmedAt = 0
        TriggerServerEvent('v-clothing:server:requestScan', 'new')
    else
        scanArmedAt = now
        Core.Notify(strings()['cl.scan_confirm'] or 'Press again to confirm the clothing scan', 'warning')
    end
end, false)
RegisterKeyMapping('vclothing_scan', 'Clothing: scan thumbnails (admin)', 'keyboard', 'F9')

-- ── Store ──────────────────────────────────────────────────────
local function openStore()
    if isOpen then return end
    local pd = exports['v-core']:GetPlayerData()
    savedApp = pd and pd.appearance and json.decode(json.encode(pd.appearance)) or {}
    preview = {}
    isOpen = true
    SetNuiFocus(true, true)   -- focus is per-resource: only the page owner may take it
    exports['v-core']:MenuOpened()
    startCam()
    -- build initial per-category data (drawable count for the tile grid) from the ped
    local ped = PlayerPedId()
    local cats = {}
    for _, c in ipairs(Config.Categories) do
        local cur = current(c)
        preview[c.key] = cur
        local count = (c.kind == 'comp')
            and GetNumberOfPedDrawableVariations(ped, c.id)
            or GetNumberOfPedPropDrawableVariations(ped, c.id)
        cats[#cats + 1] = {
            key = c.key, i18n = c.i18n, price = c.price, kind = c.kind,
            count = count, min = (c.kind == 'prop') and -1 or 0,
            drawable = cur.drawable, texture = cur.texture,
        }
    end
    Core.TriggerCallback('v-clothing:getWorn', function(wornList)
        SendNUIMessage({ action = 'open', cats = cats, worn = wornList or {},
            cash = (pd and pd.money and pd.money.cash) or 0, strings = strings() })
    end)
end

local function revert()
    -- re-apply saved components/props to undo previews (ref-aware)
    if not savedApp then return end
    for _, c in ipairs(Config.Categories) do
        local saved = c.kind == 'comp' and (savedApp.components or {})[tostring(c.id)] or (savedApp.props or {})[tostring(c.id)]
        if saved then applySaved(c, saved) end
    end
end

-- Click a tile in the grid -> preview that drawable, return its texture count.
RegisterNUICallback('select', function(data, cb)
    local cat = CatByKey[data.category]
    if not cat then cb(false); return end
    local ped = PlayerPedId()
    local drawable = tonumber(data.drawable) or 0
    local texCount = (cat.kind == 'comp')
        and GetNumberOfPedTextureVariations(ped, cat.id, drawable)
        or GetNumberOfPedPropTextureVariations(ped, cat.id, drawable)
    preview[data.category] = { drawable = drawable, texture = 0 }
    applyToPed({ kind = cat.kind, id = cat.id, drawable = drawable, texture = 0, off = (cat.kind == 'prop' and drawable < 0) })
    cb({ textureCount = math.max(0, texCount) })
end)

-- Pick a texture for the currently-previewed drawable.
RegisterNUICallback('selectTexture', function(data, cb)
    local cat = CatByKey[data.category]
    if not cat then cb(false); return end
    local cur = preview[data.category] or current(cat)
    cur.texture = tonumber(data.texture) or 0
    preview[data.category] = cur
    applyToPed({ kind = cat.kind, id = cat.id, drawable = cur.drawable, texture = cur.texture, off = (cat.kind == 'prop' and cur.drawable < 0) })
    cb('ok')
end)

-- Catalogue thumbnails (proxy to the server-side store).
RegisterNUICallback('thumbsFor', function(data, cb)
    Core.TriggerCallback('v-clothing:thumbIndex', function(list) cb(list or {}) end, data.category)
end)

RegisterNUICallback('thumb', function(data, cb)
    Core.TriggerCallback('v-clothing:thumb', function(uri) cb(uri or false) end,
        { category = data.category, drawable = data.drawable })
end)

-- Batched fetch: one round-trip for a whole viewport of tiles.
RegisterNUICallback('thumbsBatch', function(data, cb)
    Core.TriggerCallback('v-clothing:thumbs', function(out) cb(out or {}) end, data.list)
end)

RegisterNUICallback('buy', function(data, cb)
    local cur = preview[data.category] or { drawable = 0, texture = 0 }
    Core.TriggerCallback('v-clothing:buy', function(res) cb(res or false) end,
        { category = data.category, drawable = cur.drawable, texture = cur.texture })
end)

RegisterNUICallback('unequip', function(data, cb)
    Core.TriggerCallback('v-clothing:unequip', function(res) cb(res or false) end, data.category)
end)

RegisterNUICallback('rotate', function(data, cb)
    camHeading = (camHeading + (data.dx or 0) * 0.4) % 360.0
    updateCam()
    cb('ok')
end)

RegisterNUICallback('close', function(_, cb)
    isOpen = false
    SetNuiFocus(false, false)
    exports['v-core']:MenuClosed()
    stopCam()
    revert()
    cb('ok')
end)

-- ── Blips + peds + interaction ─────────────────────────────────
CreateThread(function()
    for _, loc in ipairs(Config.Locations) do
        local blip = AddBlipForCoord(loc.coords.x, loc.coords.y, loc.coords.z)
        SetBlipSprite(blip, Config.Blip.sprite); SetBlipColour(blip, Config.Blip.color)
        SetBlipScale(blip, Config.Blip.scale); SetBlipAsShortRange(blip, true)
        BeginTextCommandSetBlipName('STRING'); AddTextComponentSubstringPlayerName(strings()['cl.blip'] or 'Clothing'); EndTextCommandSetBlipName(blip)
    end
end)

CreateThread(function()
    while true do
        Wait(1500)
        local coords = GetEntityCoords(PlayerPedId())
        for i, loc in ipairs(Config.Locations) do
            local d = #(coords - vector3(loc.coords.x, loc.coords.y, loc.coords.z))
            if d < 45.0 and not (spawned[i] and DoesEntityExist(spawned[i])) then
                local model = GetHashKey(Config.PedModel)
                RequestModel(model); local t = 0; while not HasModelLoaded(model) and t < 50 do Wait(20); t = t + 1 end
                local ped = CreatePed(4, model, loc.coords.x, loc.coords.y, loc.coords.z - 1.0, loc.coords.w, false, false)
                SetEntityInvincible(ped, true); FreezeEntityPosition(ped, true); SetBlockingOfNonTemporaryEvents(ped, true)
                spawned[i] = ped; SetModelAsNoLongerNeeded(model)
            elseif d >= 60.0 and spawned[i] and DoesEntityExist(spawned[i]) then
                DeletePed(spawned[i]); spawned[i] = nil
            end
        end
    end
end)

CreateThread(function()
    while true do
        local wait = 700
        if not isOpen then
            local coords = GetEntityCoords(PlayerPedId())
            for _, loc in ipairs(Config.Locations) do
                if #(coords - vector3(loc.coords.x, loc.coords.y, loc.coords.z)) < Config.Distance then
                    wait = 0
                    BeginTextCommandDisplayHelp('STRING')
                    AddTextComponentSubstringPlayerName('~INPUT_CONTEXT~ ' .. (strings()['cl.help'] or 'Clothing'))
                    EndTextCommandDisplayHelp(0, false, true, -1)
                    if IsControlJustReleased(0, 38) then openStore() end
                    break
                end
            end
        end
        Wait(wait)
    end
end)

AddEventHandler('onResourceStop', function(resName)
    if resName ~= GetCurrentResourceName() then return end
    SetNuiFocus(false, false)
    exports['v-core']:MenuClosed()
    for _, p in pairs(spawned) do if DoesEntityExist(p) then DeletePed(p) end end
end)
