--[[
    v-loadscreen | vcore.lua

    The loading screen in v-core's admin panel.

    The manifest already marks this resource as a module, so it has been listed in the panel
    since it arrived, with nothing under it to change. This declares what an operator can
    actually decide.

    WHAT IS AND IS NOT HERE. The screen itself is HTML that the client reads before it has a
    server connection at all: config.js is a static file, so wallpapers, music tracks, tips and
    timings cannot be pushed from the panel and stay in the file, where changing them means
    editing the resource anyway. What IS declared below is the one thing the SERVER decides at
    the moment it happens - whether to echo the page's music diagnostics into the console, and
    how many lines a single player may put there.
]]

Loadscreen = Loadscreen or {}

local DEFAULT_ENABLED = true
local DEFAULT_MAX_LINES = 40

--- Whether the server console should carry the page's music diagnostics.
function Loadscreen.musicDiagnostics()
    return V.SettingBool('musicDiagnostics', DEFAULT_ENABLED)
end

--- How many diagnostic lines one player may print before being ignored for the session.
function Loadscreen.musicMaxLines()
    local n = V.SettingNumber('musicMaxLines', DEFAULT_MAX_LINES)
    return math.max(0, math.floor(n))
end

V.Module({
    label = 'Loadscreen', category = 'other',
    settings = {
        { key = 'musicDiagnostics', label = 'Music diagnostics in the console', type = 'bool',
          default = DEFAULT_ENABLED,
          hint = 'The loading screen reports why its music failed to start. Useful while '
              .. 'setting a server up, noise once it runs.' },

        { key = 'musicMaxLines', label = 'Diagnostic lines per player', type = 'number',
          default = DEFAULT_MAX_LINES, min = 0, max = 200,
          hint = 'The cap that stops one client filling the console. 0 silences reports '
              .. 'without turning the feature off.' },
    },
})
