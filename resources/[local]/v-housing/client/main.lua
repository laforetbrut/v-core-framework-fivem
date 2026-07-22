-- v-housing | client
-- Doors, blips, and the two teleports. Nothing here decides anything: the server owns the
-- tenancy, the keys, the rent and the bucket.

local Props, showBlips = {}, true
local blips = {}
local inside = nil          -- property id while indoors

local function strings()
    return Locales[(LocalPlayer.state and LocalPlayer.state.lang) or 'fr'] or Locales.fr or {}
end
local function L(k) return strings()[k] or k end

local function clearBlips()
    for _, b in ipairs(blips) do if DoesBlipExist(b) then RemoveBlip(b) end end
    blips = {}
end

local function buildBlips()
    clearBlips()
    if not showBlips then return end
    for _, p in pairs(Props) do
        if p.blip ~= false then
            local b = AddBlipForCoord(p.x + 0.0, p.y + 0.0, p.z + 0.0)
            SetBlipSprite(b, Config.Blip.sprite)
            SetBlipColour(b, Config.Blip.colour)
            SetBlipScale(b, Config.Blip.scale)
            SetBlipAsShortRange(b, true)
            BeginTextCommandSetBlipName('STRING')
            AddTextComponentSubstringPlayerName(p.label or L('house.blip'))
            EndTextCommandSetBlipName(b)
            blips[#blips + 1] = b
        end
    end
end

RegisterNetEvent('v-housing:client:props', function(list, blipsOn)
    Props = list or {}
    showBlips = blipsOn ~= false
    buildBlips()
end)

V.Ready(function()
    Wait(2000)
    TriggerServerEvent('v-housing:server:request')
end)

-- ── Teleports ──────────────────────────────────────────────────
local function fadeTo(x, y, z, h)
    DoScreenFadeOut(350)
    Wait(450)
    local ped = PlayerPedId()
    SetEntityCoords(ped, x + 0.0, y + 0.0, z + 0.0, false, false, false, false)
    SetEntityHeading(ped, h + 0.0)
    -- Freeze while the shell streams in, or the player lands under it.
    FreezeEntityPosition(ped, true)
    Wait(900)
    FreezeEntityPosition(ped, false)
    DoScreenFadeIn(500)
end

local function enter(id)
    V.Request('v-housing:enter', function(res)
        if not res or res.error then
            V.Notify(L('house.err_' .. ((res and res.error) or 'x')), 'error')
            return
        end
        inside = res.id
        fadeTo(res.shell.x, res.shell.y, res.shell.z, res.shell.h)
        V.Notify(L('house.inside'), 'info')
    end, { id = id })
end

local function leave()
    V.Request('v-housing:exit', function(res)
        if not res or res.error then return end
        inside = nil
        fadeTo(res.door.x, res.door.y, res.door.z + 0.5, 0.0)
    end)
end

-- ── Doors ──────────────────────────────────────────────────────
CreateThread(function()
    while true do
        local wait = 900
        if not inside and next(Props) then
            local me = GetEntityCoords(PlayerPedId())
            local range = tonumber(V.Setting('distance', Config.Distance)) or Config.Distance
            for id, p in pairs(Props) do
                local d = #(me - vector3(p.x + 0.0, p.y + 0.0, p.z + 0.0))
                if d < 12.0 then
                    wait = 0
                    DrawMarker(21, p.x + 0.0, p.y + 0.0, p.z + 0.4, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
                        0.28, 0.28, 0.28, 255, 122, 26, 110, false, false, 2, false, nil, nil, false)
                    if d < range then
                        BeginTextCommandDisplayHelp('STRING')
                        AddTextComponentSubstringPlayerName('~INPUT_CONTEXT~ ' .. (p.label or L('house.door')))
                        EndTextCommandDisplayHelp(0, false, true, -1)
                        if IsControlJustReleased(0, 38) then
                            -- Ask the server what this door is to this player before doing
                            -- anything: for sale, theirs, locked, or somebody else's.
                            V.Request('v-housing:info', function(info)
                                if not info or info.error then
                                    V.Notify(L('house.err_' .. ((info and info.error) or 'x')), 'error')
                                    return
                                end
                                if info.keyed and not info.locked then enter(id) return end
                                if info.locked then
                                    V.Request('v-housing:payRent', function(r)
                                        if r and r.ok then V.Notify((L('house.rent_paid')):format(r.paid), 'success')
                                        else V.Notify(L('house.err_' .. ((r and r.error) or 'x')), 'error') end
                                    end, { id = id })
                                    return
                                end
                                if info.taken then V.Notify(L('house.err_taken'), 'error') return end
                                V.Request('v-housing:acquire', function(a)
                                    if a and a.ok then
                                        V.Notify((L(info.tenancy == 'rent' and 'house.rented' or 'house.bought')):format(a.paid), 'success')
                                    else
                                        V.Notify(L('house.err_' .. ((a and a.error) or 'x')), 'error')
                                    end
                                end, { id = id })
                            end, { id = id })
                        end
                    end
                    break
                end
            end
        elseif inside then
            wait = 0
            BeginTextCommandDisplayHelp('STRING')
            AddTextComponentSubstringPlayerName('~INPUT_CONTEXT~ ' .. L('house.leave') ..
                '   ~INPUT_DETONATE~ ' .. L('house.stash'))
            EndTextCommandDisplayHelp(0, false, true, -1)
            if IsControlJustReleased(0, 38) then leave()
            elseif IsControlJustReleased(0, 47) then
                -- Storage is v-inventory's stash, keyed by property. Asked through the
                -- server so the key is checked: a client naming its own stash id could
                -- otherwise open anybody's.
                V.Request('v-housing:stash', function(res)
                    if not (res and res.ok) then
                        V.Notify(L('house.err_' .. ((res and res.error) or 'x')), 'error')
                    end
                end)
            end
        end
        Wait(wait)
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then clearBlips() end
end)

exports('IsInside', function() return inside end)
