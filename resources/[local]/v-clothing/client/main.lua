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
RegisterNetEvent('v-clothing:client:apply', function(m)
    applyToPed(m)
    local pd = exports['v-core']:GetPlayerData()
    local app = (pd and pd.appearance) or {}
    app.components = app.components or {}; app.props = app.props or {}
    if m.kind == 'comp' then
        app.components[tostring(m.id)] = { drawable = m.drawable, texture = m.texture or 0 }
    else
        app.props[tostring(m.id)] = { drawable = (m.off and -1 or m.drawable), texture = m.texture or 0 }
    end
    TriggerServerEvent('v-core:server:saveAppearance', app)
end)

-- ════════════════════════════════════════════════════════════════
--  Thumbnail scan (admin) — dress the ped in every drawable, capture it
-- ════════════════════════════════════════════════════════════════
local scanning = false

local function placeScanCam(cam, ped, fr)
    local at = GetPedBoneCoords(ped, fr.bone, 0.0, 0.0, 0.0)
    local h  = math.rad(GetEntityHeading(ped))
    local fx, fy = -math.sin(h), math.cos(h)          -- ped forward vector
    SetCamCoord(cam, at.x + fx * fr.dist, at.y + fy * fr.dist, at.z + fr.height)
    PointCamAtCoord(cam, at.x, at.y, at.z + fr.atZ)
    SetCamFov(cam, fr.fov)
end

local function restoreSlots(snap)
    for _, c in ipairs(Config.Categories) do
        local saved = snap and (c.kind == 'comp'
            and (snap.components or {})[tostring(c.id)]
            or  (snap.props or {})[tostring(c.id)])
        if saved then
            applyToPed({ kind = c.kind, id = c.id, drawable = saved.drawable, texture = saved.texture or 0, off = (c.kind == 'prop' and (saved.drawable or -1) < 0) })
        else
            applyToPed({ kind = c.kind, id = c.id, drawable = Config.NudeDefaults[c.id] or 0, texture = 0, off = (c.kind == 'prop') })
        end
    end
end

local function capture()
    local p, ok = promise.new()
    ok = pcall(function()
        exports['screenshot-basic']:requestScreenshot(
            { encoding = Config.Thumbs.encoding, quality = Config.Thumbs.quality },
            function(data) p:resolve(data) end)
    end)
    if not ok then return nil end
    return Citizen.Await(p)
end

RegisterNetEvent('v-clothing:client:startScan', function(mode, onlyCat)
    if scanning then return end
    if GetResourceState('screenshot-basic') ~= 'started' then
        TriggerServerEvent('v-clothing:server:scanDone', 0)   -- capture tool missing
        return
    end
    scanning = true
    CreateThread(function()
        local ped  = PlayerPedId()
        local pd   = exports['v-core']:GetPlayerData()
        local snap = pd and pd.appearance and json.decode(json.encode(pd.appearance)) or {}

        -- clean scene
        FreezeEntityPosition(ped, true)
        ClearPedTasksImmediately(ped)
        DisplayRadar(false)
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

        local done = 0
        for _, c in ipairs(targets) do
            local fr = Config.Framing[Config.CatFraming[c.key] or 'body']
            local n  = (c.kind == 'comp') and GetNumberOfPedDrawableVariations(ped, c.id) or GetNumberOfPedPropDrawableVariations(ped, c.id)
            for d = 0, n - 1 do
                if scanning and wanted(c.key, d) then
                    applyToPed({ kind = c.kind, id = c.id, drawable = d, texture = 0, off = false })
                    placeScanCam(cam, ped, fr)
                    Wait(Config.Thumbs.streamWait)
                    local data = capture()
                    if data then TriggerServerEvent('v-clothing:server:saveThumb', c.key, d, data) end
                    done = done + 1
                    if done % Config.Thumbs.notifyEvery == 0 then
                        TriggerServerEvent('v-clothing:server:scanProgress', done, total)
                    end
                    Wait(0)
                end
            end
        end

        -- restore
        RenderScriptCams(false, false, 0, true, false)
        DestroyCam(cam, false)
        restoreSlots(snap)
        FreezeEntityPosition(ped, false)
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
    SetNuiFocus(true, true)
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
    -- re-apply saved components/props to undo previews
    if not savedApp then return end
    for _, c in ipairs(Config.Categories) do
        local saved = savedApp and (c.kind == 'comp' and (savedApp.components or {})[tostring(c.id)] or (savedApp.props or {})[tostring(c.id)])
        if saved then
            applyToPed({ kind = c.kind, id = c.id, drawable = saved.drawable, texture = saved.texture, off = (c.kind == 'prop' and (saved.drawable or -1) < 0) })
        end
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
    for _, p in pairs(spawned) do if DoesEntityExist(p) then DeletePed(p) end end
end)
