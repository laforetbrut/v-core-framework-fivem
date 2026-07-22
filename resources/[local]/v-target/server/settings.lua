-- v-target | server/settings.lua
--
-- This module is client-side, but settings must be REGISTERED server-side: v-core owns the
-- store and the admin panel talks to the server. Values are mirrored to clients
-- automatically, so the client reads them with V.Setting(...).
--
-- Every key below is read by client/main.lua. A setting nothing reads is worse than no
-- setting, because it lies to the operator about what the panel controls.

-- Consumers ask for the capability, not the resource: a server that replaces this module
-- keeps every consumer working.
V.Provide('target')

CreateThread(function()
    -- This module may be ensured BEFORE v-core, so the core is grabbed inside the thread,
    -- once the resource is actually up.
    while GetResourceState('v-core') ~= 'started' do Wait(100) end
    local Core = exports['v-core']:GetCore()

    Core.RegisterModule('v-target', {
        label = 'Interaction eye', category = 'gameplay',
        settings = {
            { key = 'enabled', label = 'Eye enabled', type = 'bool', default = true,
              hint = 'Off stops the eye opening at all. Every option other modules registered stays registered, so turning it back on restores them without a restart.' },

            { key = 'maxDistance', label = 'Eye reach (m)', type = 'number', default = 7.0,
              min = 1, max = 25, step = 0.5,
              hint = 'How far the ray travels. An option may ask for less than this for itself; none may ask for more.' },

            { key = 'selfMenu', label = 'Self menu when pointing at nothing', type = 'bool', default = true,
              hint = 'Makes the eye the main interaction surface: with nothing targetable under the ray it offers the player their own actions instead of an empty list.' },

            { key = 'showBlocked', label = 'Show blocked actions greyed out', type = 'bool', default = true,
              hint = 'An action refused for a reason (missing tool, too far, already unlocked) is drawn inert with the reason. Job and permission gates always hide the row instead, so a civilian never learns what the police menu contains.' },

            { key = 'refreshMs', label = 'Option list refresh (ms)', type = 'number', default = 100,
              min = 0, max = 1000, step = 10,
              hint = 'How often the option list is rebuilt while the eye is open. A change of target always rebuilds immediately; this only paces the predicate pass in between. Raise it on a heavily loaded server.' },

            { key = 'boneDistance', label = 'Bone match distance (m)', type = 'number', default = 1.1,
              min = 0.2, max = 3.0, step = 0.1,
              hint = 'How close the impact point must be to a vehicle part for it to count as pointing at that part. Too generous and every hit resolves to a bone on the far side of the car.' },

            { key = 'debug', label = 'Draw interaction zones', type = 'bool', default = false,
              hint = 'Wireframes every registered box, sphere and polygon zone within 60 m. For building a map, not for a live server.' },
        },
    })
end)
