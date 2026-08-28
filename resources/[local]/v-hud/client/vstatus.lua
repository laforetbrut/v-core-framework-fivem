--[[
    v-hud | client/vstatus.lua

    The vitals rings display the numbers; v-status owns them. On this framework hunger,
    thirst and stress live in v-status, not in the player metadata the standalone HUD read,
    so without this the rings would sit at their defaults and never move.

    This feeds v-status's values into the HUD's own Needs channel - the same events its
    server would fire on a qb-core install - so nothing downstream changes. Config.Stress is
    off (see config.lua), so the HUD runs no stress gains and draws no screen effects of its
    own: v-status is the single owner of both, and the HUD is a pure readout.
]]

local function push(status)
    if type(status) ~= 'table' then return end
    -- The HUD registers these as net events; a local trigger fires the same handlers.
    TriggerEvent('vhud:client:UpdateNeeds', status.hunger, status.thirst)
    TriggerEvent('vhud:client:UpdateStress', status.stress)
end

-- v-status re-fires this locally whenever the character's status changes.
AddEventHandler('v-status:client:onUpdate', function(status) push(status) end)

-- Seed once, after v-status has loaded the character's real values, so the rings are right
-- from the first frame rather than after the first change.
CreateThread(function()
    while GetResourceState('v-status') ~= 'started' do Wait(250) end
    Wait(1500)
    local ok, status = pcall(function() return exports['v-status']:Get() end)
    if ok then push(status) end
end)
