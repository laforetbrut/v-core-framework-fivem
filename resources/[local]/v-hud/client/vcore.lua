--[[
    v-hud | client/vcore.lua

    The HUD was written against qb-core's client lifecycle: it boots on
    QBCore:Client:OnPlayerLoaded and re-reads its job/gang overrides on
    QBCore:Client:OnJobUpdate / OnGangUpdate. On this framework none of those fire, and
    v-core never raises the `isLoggedIn` state the resource-start boot poll waits on - so
    in game the HUD would never boot on a fresh connect, only on a manual resource restart.

    This translates v-core's own client lifecycle into the three events the HUD already
    listens for, so nothing downstream changes. It is inert on any other framework, where
    the v-core events simply never fire.
]]

-- Fired once the server has sent the character's full data (see v-core/client/main.lua).
AddEventHandler('v-core:client:onPlayerLoaded', function()
    -- Both boot polls (a fresh connect and a mid-session resource restart) gate on this
    -- state, which v-core does not set. Set it for the restart path...
    LocalPlayer.state:set('isLoggedIn', true, false)
    -- ...and trigger the boot directly, because character creation can outlast the
    -- resource-start poll's 30-second window on a fresh connect, leaving the state alone
    -- too late to help.
    TriggerEvent('QBCore:Client:OnPlayerLoaded')
end)

-- v-core's job is { name, grade }; it carries no qb-style "type" (leo/ems/...). The HUD
-- reads only name and type, so type stays empty, which is what a v-core install expects.
AddEventHandler('v-core:client:onJobChange', function(job)
    TriggerEvent('QBCore:Client:OnJobUpdate', { name = (job and job.name) or '', type = (job and job.type) or '' })
end)

AddEventHandler('v-core:client:onGangChange', function(gang)
    TriggerEvent('QBCore:Client:OnGangUpdate', { name = (gang and gang.name) or '' })
end)
