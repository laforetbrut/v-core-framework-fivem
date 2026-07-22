-- v-bossmenu | client
-- Opens the panel on a keybind. Nothing here decides anything: the server answers
-- "you are not a boss" and this file only ever relays.

local open = false

local function strings()
    return Locales[(LocalPlayer.state and LocalPlayer.state.lang) or 'fr'] or Locales.fr or {}
end
local function L(k) return strings()[k] or k end

local function close()
    if not open then return end
    open = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
    if GetResourceState('v-core') == 'started' then
        pcall(function() exports['v-core']:MenuClosed('v-bossmenu') end)
    end
end

local function refresh(cb)
    V.Request('v-bossmenu:open', function(data)
        if not data or data.error then
            if cb then cb(false) end
            return
        end
        SendNUIMessage({ action = 'data', data = data, strings = strings() })
        if cb then cb(true) end
    end)
end

local function openMenu()
    if open then close() return end
    V.Request('v-bossmenu:open', function(data)
        if not data or data.error then
            -- The only failure a player should ever see here: they are not a boss.
            V.Notify(L('boss.err_rank'), 'error')
            return
        end
        open = true
        SetNuiFocus(true, true)
        if GetResourceState('v-core') == 'started' then
            pcall(function() exports['v-core']:MenuOpened('v-bossmenu') end)
        end
        SendNUIMessage({ action = 'open', data = data, strings = strings() })
    end)
end

RegisterCommand('vboss', openMenu, false)
RegisterKeyMapping('vboss', 'Open the boss menu', 'keyboard', Config.Key or 'F6')

-- ── NUI callbacks ──────────────────────────────────────────────
RegisterNUICallback('close', function(_, cb) close(); cb('ok') end)

-- One relay for every action: the server names the error, this shows it and re-reads the
-- whole state rather than patching the DOM from a guess about what changed.
local function act(name, payload, cb)
    V.Request(name, function(res)
        if res and res.ok then
            if res.paid ~= nil then
                V.Notify((L('boss.paid_n')):format(res.paid, res.total), res.short and 'warning' or 'success')
                if res.short then V.Notify(L('boss.err_funds'), 'error') end
            end
            refresh()
        else
            V.Notify(L('boss.err_' .. ((res and res.error) or 'x')), 'error')
        end
        cb('ok')
    end, payload)
end

RegisterNUICallback('hire',     function(d, cb) act('v-bossmenu:hire', { cid = d.cid, grade = d.grade }, cb) end)
RegisterNUICallback('fire',     function(d, cb) act('v-bossmenu:fire', { cid = d.cid }, cb) end)
RegisterNUICallback('setGrade', function(d, cb) act('v-bossmenu:setGrade', { cid = d.cid, grade = d.grade }, cb) end)
RegisterNUICallback('deposit',  function(d, cb) act('v-bossmenu:deposit', { amount = d.amount }, cb) end)
RegisterNUICallback('withdraw', function(d, cb) act('v-bossmenu:withdraw', { amount = d.amount }, cb) end)
RegisterNUICallback('refresh',  function(_, cb) refresh(); cb('ok') end)

RegisterNUICallback('paySalaries', function(_, cb)
    V.Request('v-bossmenu:paySalaries', function(res)
        if res and res.ok then
            V.Notify((L('boss.paid_n')):format(res.paid, res.total), res.short and 'warning' or 'success')
            if res.short then V.Notify(L('boss.err_funds'), 'error') end
            refresh()
        else
            V.Notify(L('boss.err_' .. ((res and res.error) or 'x')), 'error')
        end
        cb('ok')
    end)
end)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() and open then SetNuiFocus(false, false) end
end)

-- ── Theme ──────────────────────────────────────────────────────
local function pushTheme()
    if GetResourceState('v-ui') ~= 'started' then return end
    pcall(function() exports['v-ui']:Push() end)
end
AddEventHandler('v-ui:client:themeChanged', function() pushTheme() end)
CreateThread(function() Wait(4000); pushTheme() end)
