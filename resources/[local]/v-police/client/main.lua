-- v-police | client
-- Cuff/escort/jail effects on the detainee, and the officer's panel. Nothing here decides
-- anything: the server tells this file what state a player is in, and this file makes the
-- ped look and behave that way.

local cuffed, escortedBy = false, nil
local jailUntil = 0
local open = false

local function strings()
    return Locales[(LocalPlayer.state and LocalPlayer.state.lang) or 'fr'] or Locales.fr or {}
end
local function L(k) return strings()[k] or k end

-- ── Cuffs ──────────────────────────────────────────────────────
local CUFF_DICT, CUFF_ANIM = 'mp_arresting', 'idle'

local function playCuffAnim()
    RequestAnimDict(CUFF_DICT)
    local t = 0
    while not HasAnimDictLoaded(CUFF_DICT) and t < 100 do Wait(10); t = t + 1 end
    if HasAnimDictLoaded(CUFF_DICT) then
        TaskPlayAnim(PlayerPedId(), CUFF_DICT, CUFF_ANIM, 8.0, -8.0, -1, 49, 0, false, false, false)
    end
end

RegisterNetEvent('v-police:client:cuffed', function(on)
    cuffed = on and true or false
    local ped = PlayerPedId()
    if cuffed then
        playCuffAnim()
        SetEnableHandcuffs(ped, true)
        DisablePlayerFiring(PlayerId(), true)
        SetPedCanPlayGestureAnims(ped, false)
    else
        ClearPedTasks(ped)
        SetEnableHandcuffs(ped, false)
        DisablePlayerFiring(PlayerId(), false)
        SetPedCanPlayGestureAnims(ped, true)
        DetachEntity(ped, true, false)
    end
end)

RegisterNetEvent('v-police:client:escort', function(officerSrc)
    escortedBy = officerSrc
    local ped = PlayerPedId()
    if not officerSrc then DetachEntity(ped, true, false) return end
    local opl = GetPlayerFromServerId(officerSrc)
    local oped = opl ~= -1 and GetPlayerPed(opl) or 0
    if oped and oped ~= 0 then
        AttachEntityToEntity(ped, oped, GetPedBoneIndex(oped, Config.Escort.bone),
            Config.Escort.x, Config.Escort.y, Config.Escort.z, 0.0, 0.0, 0.0,
            false, false, false, false, 2, true)
    end
end)

-- A cuffed player keeps the animation and cannot draw, run or drive off. Only ticks while
-- actually cuffed, so it costs nothing the rest of the time.
CreateThread(function()
    while true do
        if cuffed then
            local ped = PlayerPedId()
            DisableControlAction(0, 24, true)   -- attack
            DisableControlAction(0, 25, true)   -- aim
            DisableControlAction(0, 21, true)   -- sprint
            DisableControlAction(0, 22, true)   -- jump
            DisableControlAction(0, 23, true)   -- enter vehicle
            DisableControlAction(0, 75, true)   -- exit vehicle
            if not IsEntityPlayingAnim(ped, CUFF_DICT, CUFF_ANIM, 3) then playCuffAnim() end
            Wait(0)
        else
            Wait(400)
        end
    end
end)

-- ── Jail ───────────────────────────────────────────────────────
RegisterNetEvent('v-police:client:jail', function(minutes, jail)
    jailUntil = GetGameTimer() + math.max(0, math.floor(tonumber(minutes) or 0)) * 60000
    local ped = PlayerPedId()
    -- Freeze while the world streams in, or the player lands under the map.
    DoScreenFadeOut(400)
    Wait(500)
    SetEntityCoords(ped, jail.x + 0.0, jail.y + 0.0, jail.z + 0.0, false, false, false, false)
    SetEntityHeading(ped, jail.heading + 0.0)
    Wait(600)
    DoScreenFadeIn(600)
    V.Notify((L('pol.jailed')):format(math.floor(minutes)), 'error')
end)

CreateThread(function()
    while true do
        if jailUntil > 0 then
            local left = jailUntil - GetGameTimer()
            if left <= 0 then
                jailUntil = 0
                TriggerServerEvent('v-police:server:released')
                local j = Config.Jail.release
                DoScreenFadeOut(400); Wait(500)
                SetEntityCoords(PlayerPedId(), j.x + 0.0, j.y + 0.0, j.z + 0.0, false, false, false, false)
                SetEntityHeading(PlayerPedId(), j.heading + 0.0)
                Wait(600); DoScreenFadeIn(600)
                V.Notify(L('pol.released'), 'success')
            end
            Wait(2000)
        else
            Wait(4000)
        end
    end
end)

-- Prison blip.
V.Ready(function()
    Wait(2500)
    if V.SettingBool('jailBlip', true) then
        local b = AddBlipForCoord(Config.Jail.x + 0.0, Config.Jail.y + 0.0, Config.Jail.z + 0.0)
        SetBlipSprite(b, Config.BlipJail.sprite)
        SetBlipColour(b, Config.BlipJail.colour)
        SetBlipScale(b, 0.8); SetBlipAsShortRange(b, true)
        BeginTextCommandSetBlipName('STRING')
        AddTextComponentSubstringPlayerName(Config.BlipJail.label)
        EndTextCommandSetBlipName(b)
    end
    -- Somebody who relogs mid-sentence is put back inside.
    V.Request('v-police:jailLeft', function(left)
        if (tonumber(left) or 0) > 0 then
            TriggerEvent('v-police:client:jail', left, Config.Jail)
        end
    end)
end)

-- ── Officer panel ──────────────────────────────────────────────
local function closePanel()
    if not open then return end
    open = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
    if GetResourceState('v-core') == 'started' then
        pcall(function() exports['v-core']:MenuClosed('v-police') end)
    end
end

--- The nearest other player, which is who every street action applies to.
local function nearestPlayer()
    local me = PlayerPedId()
    local myCoords = GetEntityCoords(me)
    local best, bestD = nil, 6.0
    for _, pid in ipairs(GetActivePlayers()) do
        local ped = GetPlayerPed(pid)
        if ped ~= me and ped ~= 0 then
            local d = #(myCoords - GetEntityCoords(ped))
            if d < bestD then best, bestD = GetPlayerServerId(pid), d end
        end
    end
    return best
end

local function openPanel()
    if open then closePanel() return end
    V.Request('v-police:charges', function(res)
        if not res or res.error then
            V.Notify(L('pol.err_' .. ((res and res.error) or 'x')), 'error')
            return
        end
        open = true
        SetNuiFocus(true, true)
        if GetResourceState('v-core') == 'started' then
            pcall(function() exports['v-core']:MenuOpened('v-police') end)
        end
        SendNUIMessage({ action = 'open', charges = res.charges or {},
                         target = nearestPlayer(), strings = strings() })
    end)
end

RegisterCommand('vpolice', openPanel, false)
RegisterKeyMapping('vpolice', 'Open the police panel', 'keyboard', Config.Key or 'F5')

local function relay(name, payload, cb, after)
    V.Request(name, function(res)
        if res and res.ok then
            if after then after(res) end
        else
            V.Notify(L('pol.err_' .. ((res and res.error) or 'x')), 'error')
        end
        if cb then cb('ok') end
    end, payload)
end

RegisterNUICallback('close', function(_, cb) closePanel(); cb('ok') end)

RegisterNUICallback('cuff', function(_, cb)
    relay('v-police:cuff', { target = nearestPlayer() }, cb, function(res)
        V.Notify(L(res.cuffed and 'pol.cuffed' or 'pol.uncuffed'), 'success')
    end)
end)

RegisterNUICallback('escort', function(_, cb)
    relay('v-police:escort', { target = nearestPlayer() }, cb, function(res)
        V.Notify(L(res.escorting and 'pol.escorting' or 'pol.escort_off'), 'success')
    end)
end)

RegisterNUICallback('search', function(_, cb)
    relay('v-police:search', { target = nearestPlayer() }, cb, function(res)
        SendNUIMessage({ action = 'search', data = res })
    end)
end)

RegisterNUICallback('seize', function(d, cb)
    relay('v-police:seize', { target = nearestPlayer(), item = d.item, count = d.count }, cb, function()
        V.Notify(L('pol.seized_ok'), 'success')
    end)
end)

RegisterNUICallback('book', function(d, cb)
    relay('v-police:book', { target = nearestPlayer(), codes = d.codes, notes = d.notes }, cb, function(res)
        V.Notify((L('pol.booked_ok')):format(res.fine, res.jail), 'success')
        closePanel()
    end)
end)

RegisterNUICallback('lookup', function(d, cb)
    relay('v-police:lookup', { query = d.query }, cb, function(res)
        SendNUIMessage({ action = 'lookup', data = res })
    end)
end)

RegisterNUICallback('warrant', function(d, cb)
    relay('v-police:warrant', { citizenid = d.citizenid, reason = d.reason, clear = d.clear }, cb, function()
        V.Notify(L('pol.warrant_ok'), 'success')
    end)
end)

RegisterNUICallback('warrants', function(_, cb)
    relay('v-police:warrants', nil, cb, function(res)
        SendNUIMessage({ action = 'warrants', rows = res.rows or {} })
    end)
end)

RegisterNUICallback('impound', function(_, cb)
    local veh = GetVehiclePedIsIn(PlayerPedId(), false)
    if veh == 0 then
        veh = GetClosestVehicle(GetEntityCoords(PlayerPedId()), 8.0, 0, 71)
    end
    if not veh or veh == 0 then V.Notify(L('pol.err_novehicle'), 'error'); cb('ok'); return end
    relay('v-police:impound', { netid = VehToNet(veh) }, cb, function()
        V.Notify(L('pol.impounded'), 'success')
    end)
end)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() and open then SetNuiFocus(false, false) end
end)

local function pushTheme()
    if GetResourceState('v-ui') ~= 'started' then return end
    pcall(function() exports['v-ui']:Push() end)
end
AddEventHandler('v-ui:client:themeChanged', function() pushTheme() end)
CreateThread(function() Wait(4000); pushTheme() end)
