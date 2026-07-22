-- v-ui | server
-- Resolves the theme (config + admin settings) into CSS custom properties and writes them
-- to `theme-vars.css`, which every NUI page links after `theme.css`.
--
-- Why a generated file rather than pushing variables into each page: a NUI page can only
-- talk to the resource that owns it, so there is no way for v-ui to message v-inventory's
-- page directly. A stylesheet every page already links is the one channel that reaches
-- all of them, and it survives a page reload for free.
-- v-ui is ensured BEFORE v-core (every NUI needs the stylesheet first), so the core is
-- resolved lazily rather than at file scope.
local Core
local function core()
    if not Core then Core = exports['v-core']:GetCore() end
    return Core
end

local VARS_FILE = 'theme-vars.css'
local version = 0        -- bumped on every rebuild; clients cache-bust with it

-- ── Colour helpers ─────────────────────────────────────────────
local function hexToRgb(hex)
    hex = tostring(hex or ''):gsub('#', '')
    if #hex ~= 6 then return 255, 122, 26 end
    return tonumber(hex:sub(1, 2), 16), tonumber(hex:sub(3, 4), 16), tonumber(hex:sub(5, 6), 16)
end

local function rgba(hex, a)
    local r, g, b = hexToRgb(hex)
    return ('rgba(%d, %d, %d, %s)'):format(r, g, b, a)
end

--- Mix `hex` toward white (t > 0) or black (t < 0). Used to derive the light/dark members
--- of the accent family from a single colour, so an operator picks ONE and gets the set.
local function shade(hex, t)
    local r, g, b = hexToRgb(hex)
    local target = t >= 0 and 255 or 0
    local k = math.abs(t)
    r = math.floor(r + (target - r) * k + 0.5)
    g = math.floor(g + (target - g) * k + 0.5)
    b = math.floor(b + (target - b) * k + 0.5)
    return ('#%02x%02x%02x'):format(r, g, b)
end

-- ── Resolve ────────────────────────────────────────────────────
local function S(key, fallback)
    if GetResourceState('v-core') ~= 'started' then return fallback end
    return core().GetSetting('v-ui', key, fallback)
end

--- Build the variable list for one theme. `o` is a per-module override row (or nil for
--- the global theme); anything it leaves nil falls through to the global setting.
--- `partial` emits ONLY what the override actually changes, so a module block stays small
--- and everything else keeps inheriting.
local function buildVars(o, partial)
    local presetKey = (o and o.preset) or S('preset', Config.DefaultPreset)
    local base = Config.Presets[Config.DefaultPreset] or {}
    local p = Config.Presets[presetKey] or base

    -- a preset only declares what it changes; the default fills the rest
    local function pick(k) return p[k] or base[k] end

    -- The accent override only applies when an operator DELIBERATELY set it. A colour
    -- setting has to carry a sensible default for the picker, so "is it the default value"
    -- cannot answer this — ask v-core whether the key was actually stored.
    local accent = pick('accent')
    if GetResourceState('v-core') == 'started' then
        local raw = core().GetRawSetting('v-ui', 'accent')
        if type(raw) == 'string' and raw:match('^#%x%x%x%x%x%x$') then accent = raw end
    end
    local accent2 = pick('accent2')
    if o and o.accent and tostring(o.accent):match('^#%x%x%x%x%x%x$') then
        accent = o.accent
        -- An accent override without a preset would keep the GLOBAL gradient partner,
        -- producing a two-hue gradient (a green accent ending in orange). Derive the
        -- partner from the chosen colour instead, unless a preset supplied its own.
        if not o.preset then accent2 = shade(accent, -0.30) end
    end
    local bg      = pick('bg')
    local panel   = pick('panel')
    local text    = pick('text')

    local radius  = (o and o.radius) or S('radius', Config.Shape.radius)
    local density = S('density', Config.Shape.density)
    local motion  = (o and o.motion) or S('motion', Config.Motion.speed)
    local alpha   = (o and o.panel_alpha) or S('panelAlpha', Config.Surface.panelAlpha)
    local backA   = (o and o.backdrop_alpha) or S('backdropAlpha', Config.Surface.backdropAlpha)
    local fscale  = (o and o.font_scale) or S('fontScale', Config.Font.scale)

    -- which keys this override actually touches; in `partial` mode nothing else is emitted
    local touched = nil
    if partial and o then
        touched = {}
        if o.preset then touched.palette = true end
        if o.accent then touched.accent = true end
        if o.radius then touched.radius = true end
        if o.motion then touched.motion = true end
        if o.panel_alpha then touched.palette = true end
        if o.backdrop_alpha then touched.backdrop = true end
        if o.font_scale then touched.font = true end
    end
    local function want(group)
        if not touched then return true end
        return touched[group] == true
    end

    local function r(px) return ('%.0fpx'):format(px * radius) end
    local function ms(v) return motion <= 0 and '0ms' or ('%.0fms'):format(v * (1 / math.max(0.05, motion))) end

    local out = {}
    local function add(k, v) out[#out + 1] = ('  %s: %s;'):format(k, v) end

    -- backgrounds derived from one base colour, so a preset stays coherent
    if want('palette') then
    add('--v-bg-900', bg)
    add('--v-bg-800', shade(bg, 0.03))
    add('--v-bg-700', shade(bg, 0.06))
    add('--v-bg-600', shade(bg, 0.10))
    add('--v-bg-500', shade(bg, 0.14))
    add('--v-bg-sunk', shade(bg, -0.35))

    add('--v-panel',   rgba(panel, alpha))
    add('--v-panel-2', rgba(shade(panel, 0.05), alpha))
    add('--v-panel-3', rgba(shade(panel, 0.10), alpha))
    add('--v-line',    rgba(shade(panel, 0.35), 0.55))
    add('--v-line-2',  rgba(shade(panel, 0.50), 0.40))

    add('--v-text',       text)
    add('--v-text-dim',   rgba(text, 0.72))
    add('--v-text-faint', rgba(text, 0.46))
    add('--v-ink',        shade(bg, -0.5))
    end

    -- the whole accent family from one colour
    if want('palette') or want('accent') then
    add('--v-accent',       accent)
    add('--v-accent-300',   shade(accent, 0.28))
    add('--v-accent-600',   accent2)
    add('--v-accent-700',   shade(accent2, -0.25))
    add('--v-accent-soft',  rgba(accent, 0.12))
    add('--v-accent-line',  rgba(accent, 0.42))
    add('--v-accent-glow',  rgba(accent, 0.50))
    add('--v-grad-accent',  ('linear-gradient(135deg, %s 0%%, %s 100%%)'):format(accent, accent2))
    add('--v-grad-soft',    ('linear-gradient(135deg, %s 0%%, %s 100%%)'):format(rgba(accent, 0.16), rgba(accent2, 0.10)))

    end

    if want('palette') then
    for _, k in ipairs({ 'success', 'danger', 'warning', 'info' }) do
        local c = pick(k)
        add('--v-' .. k, c)
        add(('--v-%s-300'):format(k), shade(c, 0.28))
    end
    for k, c in pairs(Config.Rarity) do add('--v-rar-' .. k, c) end
    end

    if want('radius') then
        add('--v-r-sm', r(8));  add('--v-r-md', r(12))
        add('--v-r-lg', r(16)); add('--v-r-xl', r(22))
    end

    if want('motion') then
        add('--v-t-fast', ms(120)); add('--v-t-base', ms(200)); add('--v-t-slow', ms(360))
    end

    if want('font') then
        add('--v-fs', ('%.3f'):format(fscale))
    end

    if want('backdrop') then
        add('--v-backdrop-a', ('%.3f'):format(backA))
    end

    -- global-only: typography families, density and the feature switches
    if not partial then
        add('--v-font-display', Config.Font.display)
        add('--v-font-body',    Config.Font.body)
        add('--v-density',      ('%.3f'):format(density))
        add('--v-brackets',  (S('brackets', Config.Shape.brackets) and 'block' or 'none'))
        add('--v-streak',    (S('topStreak', Config.Shape.topStreak) and 'block' or 'none'))
        add('--v-grain',     (S('grain', Config.Surface.grain) and '0.04' or '0'))
    end

    return out
end

--- The whole stylesheet: the global theme, then one scoped block per module that overrides
--- it. `theme.js` stamps the owning resource onto <html>, so a page picks up its own block
--- and inherits everything it did not override.
local function resolve()
    local parts = {
        '/* v-ui — generated from config.lua, admin settings and the per-module overrides',
        '   (Admin -> Editor -> Module themes). Do not edit by hand: it is rewritten on',
        '   every theme change. */',
        ':root {',
        table.concat(buildVars(nil, false), '\n'),
        '}',
        '',
    }

    local overrides = (GetResourceState('v-world') == 'started' and exports['v-world']:IsReady())
        and exports['v-world']:GetUiThemes() or {}
    for _, o in ipairs(overrides) do
        if o.enabled == 1 and o.module and o.module ~= '' then
            local vars = buildVars(o, true)
            if #vars > 0 then
                parts[#parts + 1] = ('/* %s */'):format(o.module)
                parts[#parts + 1] = (':root[data-vmod="%s"] {'):format(o.module)
                parts[#parts + 1] = table.concat(vars, '\n')
                parts[#parts + 1] = '}'
                parts[#parts + 1] = ''
            end
        end
    end
    return table.concat(parts, '\n')
end

local function rebuild()
    local css = resolve()
    SaveResourceFile(GetCurrentResourceName(), VARS_FILE, css, -1)
    version = version + 1
    TriggerClientEvent('v-ui:client:theme', -1, version)
    return true
end

exports('Rebuild', function() return rebuild() end)
exports('GetVersion', function() return version end)
exports('GetPresets', function()
    local out = {}
    for k, p in pairs(Config.Presets) do out[#out + 1] = { key = k, label = p.label or k } end
    table.sort(out, function(a, b) return a.key < b.key end)
    return out
end)

-- ── Settings ───────────────────────────────────────────────────
CreateThread(function()
    while GetResourceState('v-core') ~= 'started' do Wait(100) end
    Wait(2600)

    local presetKeys = {}
    for k in pairs(Config.Presets) do presetKeys[#presetKeys + 1] = k end
    table.sort(presetKeys)

    core().RegisterModule('v-ui', {
        label = 'Interface & theme', category = 'other',
        settings = {
            { key = 'preset',        label = 'Colour preset',        type = 'select', default = Config.DefaultPreset, options = presetKeys },
            { key = 'accent',        label = 'Accent override',      type = 'color',  default = (Config.Presets[Config.DefaultPreset] or {}).accent,
              hint = 'Overrides the preset accent. The whole highlight family is derived from it.' },
            { key = 'radius',        label = 'Corner roundness',     type = 'number', default = Config.Shape.radius, min = 0, max = 2.5 },
            { key = 'density',       label = 'Density',              type = 'number', default = Config.Shape.density, min = 0.6, max = 1.6 },
            { key = 'motion',        label = 'Animation speed',      type = 'number', default = Config.Motion.speed, min = 0, max = 3,
              hint = '0 disables all motion (accessibility, and frames back on a weak client).' },
            { key = 'panelAlpha',    label = 'Panel opacity',        type = 'number', default = Config.Surface.panelAlpha, min = 0.5, max = 1 },
            { key = 'backdropAlpha', label = 'Backdrop darkness',    type = 'number', default = Config.Surface.backdropAlpha, min = 0, max = 1 },
            { key = 'fontScale',     label = 'Font scale',           type = 'number', default = Config.Font.scale, min = 0.8, max = 1.4 },
            { key = 'brackets',      label = 'Corner brackets',      type = 'bool',   default = Config.Shape.brackets },
            { key = 'topStreak',     label = 'Panel top light',      type = 'bool',   default = Config.Shape.topStreak },
            { key = 'grain',         label = 'Film grain',           type = 'bool',   default = Config.Surface.grain },
        },
    })
    rebuild()
end)

AddEventHandler('v-core:server:settingChanged', function(mod)
    if mod == 'v-ui' then rebuild() end
end)

-- a per-module override was edited in the admin panel
AddEventHandler('v-world:server:changed', function(domain)
    if domain == nil or domain == 'uitheme' then rebuild() end
end)

-- A joining client needs the current version so its pages link the right cache-buster.
RegisterNetEvent('v-ui:server:request', function()
    TriggerClientEvent('v-ui:client:theme', source, version)
end)
